#!/usr/bin/env python3
"""Run reproducible local checks without exposing command output or credentials."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from uuid import uuid4

PHASES = ('contracts', 'backend', 'integration', 'frontend')
EXPORTS = ('abi/PrepaidVault.json', 'abi/MockUSDC.json', 'abi/MockYieldAdapter.json',
           'check-in.types.json', 'check-in.fixture.json', 'check-in.schema.json')


def local_rpc(url):
    try:
        p = urlsplit(url)
        _ = p.port
        return (p.scheme == 'http' and p.hostname in {'localhost', '127.0.0.1'}
                and p.username is None and p.password is None and not p.query
                and not p.fragment and p.path in ('', '/'))
    except ValueError:
        return False


def chain_id(url):
    request = Request(url, json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'eth_chainId',
                                       'params': []}).encode(), {'Content-Type': 'application/json'})
    try:
        with urlopen(request, timeout=3) as response:
            result = json.load(response)
        return int(result['result'], 16)
    except (OSError, ValueError, KeyError, TypeError):
        return None


def schema_url(url, schema):
    p = urlsplit(url)
    if not p.scheme.startswith('postgresql') or not p.hostname or not p.path.strip('/'):
        raise ValueError('TEST_DATABASE_URL must identify a PostgreSQL database')
    query = parse_qsl(p.query, keep_blank_values=True)
    if any(k == 'options' for k, _ in query):
        raise ValueError('database URL must not include options')
    query.append(('options', '-csearch_path=' + schema))
    return urlunsplit((p.scheme, p.netloc, p.path, urlencode(query), p.fragment))


def run_process(cmd, cwd, env, timeout):
    """Capture output and terminate the owned process tree on timeout."""
    options = {'start_new_session': os.name != 'nt'}
    if os.name == 'nt':
        options['creationflags'] = subprocess.CREATE_NEW_PROCESS_GROUP
    proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, **options)
    try:
        output, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        if os.name == 'nt':
            try:
                killed = subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                        timeout=5, check=False)
            except subprocess.TimeoutExpired as exc:
                proc.kill()
                raise OSError('process tree termination timed out') from exc
            if killed.returncode:
                proc.kill()
                raise OSError('could not terminate process tree')
        else:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate(timeout=5)
        raise
    return subprocess.CompletedProcess(cmd, proc.returncode, output)


class Runner:
    def __init__(self, args):
        self.args = args
        self.root = args.repo_root.resolve()
        self.results = []
        self.env = os.environ.copy()
        self.db = self.env.get(args.database_url_env, '')
        self.rpc = args.rpc_url or self.env.get('CONTRACT_TEST_RPC', '')
        self.node = args.node_executable
        self.hardhat = str(self.root / 'contracts/node_modules/hardhat/dist/src/cli.js')
        self.flutter = shutil.which('flutter') or 'flutter'
        self.uv = shutil.which('uv') or 'uv'
        # On Windows subprocess cannot directly execute .bat files without a shell.
        if os.name == 'nt' and self.flutter.lower().endswith('.bat'):
            self.flutter = [os.environ.get('COMSPEC', 'cmd.exe'), '/d', '/s', '/c', self.flutter]
        else:
            self.flutter = [self.flutter]

    def record(self, phase, name, status, detail='', duration=0, attempts=1):
        self.results.append(dict(phase=phase, name=name, status=status, detail=detail,
                                 seconds=round(duration, 2), attempts=attempts))
        print(f'{phase}: {name}: {status}' + (f' ({detail})' if detail else ''), flush=True)
        return status == 'pass'

    def run(self, phase, name, cmd, cwd, env=None, forbid_skips=False):
        start = time.monotonic()
        status, detail = 'fail', ''
        for attempt in range(1, self.args.retries + 2):
            try:
                result = run_process(cmd, cwd, env or self.env, self.args.timeout)
                if result.returncode:
                    detail = f'exit code {result.returncode}; subprocess output withheld'
                elif forbid_skips and re.search(
                    rb'^\s*[1-9]\d*\s+skipped\b|,\s*[1-9]\d*\s+skipped\b|\+\d+\s+~[1-9]\d*|^\s*[1-9]\d*\s+pending\s*$|^\s*SKIPPED\b',
                    result.stdout,
                    re.I | re.M,
                ):
                    detail = 'test suite reported skipped tests; subprocess output withheld'
                else:
                    status, detail = 'pass', ''
                    break
            except subprocess.TimeoutExpired:
                detail = f'timed out after {self.args.timeout}s; subprocess output withheld'
            except OSError:
                detail = 'executable unavailable or could not start'
                status = 'blocked'
                break
        return self.record(phase, name, status, detail, time.monotonic()-start, attempt)

    def contracts(self):
        p, cwd = 'contracts', self.root / 'contracts'
        ok = self.run(p, 'Node 24 version', [self.node, '-e',
                      "if (process.versions.node.split('.')[0] !== '24') process.exit(1)"], cwd)
        if not ok:
            for n in ('typecheck', 'build', 'contract tests', 'export drift'):
                self.record(p, n, 'blocked', 'Node 24 unavailable')
            return False
        t = self.run(p, 'typecheck', [self.node, 'node_modules/typescript/bin/tsc', '--noEmit'], cwd)
        b = self.run(p, 'build', [self.node, self.hardhat, 'build'], cwd)
        test = self.run(p, 'contract tests', [self.node, self.hardhat, 'test'], cwd, forbid_skips=True) if b else self.record(p, 'contract tests', 'blocked', 'build failed')
        if b:
            try:
                with tempfile.TemporaryDirectory(prefix='prepaidguard-export-') as tmp:
                    tmp = Path(tmp)
                    # Copy dependencies too: ESM resolves packages relative to the copied scripts.
                    shutil.copytree(cwd, tmp / 'contracts', ignore=shutil.ignore_patterns('.git'))
                    shutil.copytree(self.root / 'shared', tmp / 'shared')
                    export = self.run(p, 'isolated export', [self.node, str(tmp / 'contracts/node_modules/hardhat/dist/src/cli.js'), 'run', 'scripts/export.ts'], tmp / 'contracts')
                    drift = export and all((self.root / 'shared' / f).read_bytes() == (tmp / 'shared' / f).read_bytes() for f in EXPORTS)
                    self.record(p, 'export drift', 'pass' if drift else 'fail', '' if drift else 'generated files differ or export failed')
            except OSError:
                drift = self.record(p, 'export drift', 'blocked', 'isolated copy or comparison failed')
        else:
            drift = self.record(p, 'export drift', 'blocked', 'build failed')
        return bool(t and b and test and drift)

    def backend(self):
        p, cwd = 'backend', self.root / 'backend'
        checks = [self.run(p, 'lint', [self.uv, 'run', '--locked', 'ruff', 'check', '.'], cwd),
                  self.run(p, 'format', [self.uv, 'run', '--locked', 'ruff', 'format', '--check', '.'], cwd)]
        if not self.db:
            for n in ('migration schema setup', 'migration upgrade', 'migration check', 'backend tests'):
                self.record(p, n, 'blocked', f'{self.args.database_url_env} is unset')
            return False
        schema = 'pp_validate_' + uuid4().hex
        try:
            scoped = schema_url(self.db, schema)
        except ValueError as e:
            self.record(p, 'migration schema setup', 'blocked', str(e))
            for n in ('migration upgrade', 'migration check', 'backend tests'):
                self.record(p, n, 'blocked', 'invalid test database URL')
            return False
        env = self.env.copy()
        env['TEST_DATABASE_URL'] = self.db
        env['DATABASE_URL'] = self.db
        env['VALIDATION_SCHEMA'] = schema
        code = ("import os; from sqlalchemy import create_engine, text; "
                "e=create_engine(os.environ['DATABASE_URL']); "
                "c=e.begin(); conn=c.__enter__(); "
                "conn.execute(text('CREATE SCHEMA \"'+os.environ['VALIDATION_SCHEMA']+'\"')); "
                "c.__exit__(None,None,None); e.dispose()")
        try:
            created = self.run(p, 'migration schema setup', [self.uv, 'run', '--locked', 'python', '-c', code], cwd, env)
            if created:
                env['DATABASE_URL'] = scoped
                up = self.run(p, 'migration upgrade', [self.uv, 'run', '--locked', 'alembic', 'upgrade', 'head'], cwd, env)
                check = self.run(p, 'migration check', [self.uv, 'run', '--locked', 'alembic', 'check'], cwd, env) if up else self.record(p, 'migration check', 'blocked', 'migration upgrade failed')
                checks.extend([up, check])
            else:
                self.record(p, 'migration upgrade', 'blocked', 'schema setup failed')
                self.record(p, 'migration check', 'blocked', 'schema setup failed')
                checks.append(False)
        finally:
            env['DATABASE_URL'] = self.db
            drop = code.replace('CREATE SCHEMA', 'DROP SCHEMA IF EXISTS').replace("+'\"'));", "+'\" CASCADE')); ")
            cleanup = self.run(p, 'migration schema cleanup', [self.uv, 'run', '--locked', 'python', '-c', drop], cwd, env)
            if not cleanup:
                self.results[-1]['detail'] += '; temporary schema ' + schema
            checks.append(cleanup)
        env['DATABASE_URL'] = self.db
        checks.append(self.run(p, 'backend tests', [self.uv, 'run', '--locked', 'pytest', '-q', '--ignore=tests/test_live_contract.py'], cwd, env, True))
        return all(checks)

    def integration(self, build_ok):
        p, cwd = 'integration', self.root / 'backend'
        if not self.db:
            return self.record(p, 'live contract and API tests', 'blocked', f'{self.args.database_url_env} is unset')
        if not build_ok:
            return self.record(p, 'live contract and API tests', 'blocked', 'contract build was not successful')
        rpc = self.rpc or ('http://127.0.0.1:8545' if self.args.start_local_evm else '')
        if not local_rpc(rpc):
            return self.record(p, 'live contract and API tests', 'blocked', 'RPC must be an HTTP loopback URL without credentials')
        proc = None
        try:
            if self.args.start_local_evm:
                parsed = urlsplit(rpc)
                if chain_id(rpc) is not None:
                    return self.record(p, 'live contract and API tests', 'blocked', 'RPC already occupied; refusing to own existing process')
                options = {'start_new_session': os.name != 'nt'}
                if os.name == 'nt':
                    options['creationflags'] = subprocess.CREATE_NEW_PROCESS_GROUP
                proc = subprocess.Popen([self.node, self.hardhat, 'node', '--hostname', parsed.hostname,
                                         '--port', str(parsed.port or 8545)], cwd=self.root / 'contracts',
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **options)
                deadline = time.monotonic() + 30
                while proc.poll() is None and time.monotonic() < deadline and chain_id(rpc) is None:
                    time.sleep(.25)
            if proc is not None and proc.poll() is not None:
                return self.record(p, 'live contract and API tests', 'blocked', 'managed node failed to start')
            if chain_id(rpc) != 31337:
                return self.record(p, 'live contract and API tests', 'blocked', 'RPC unavailable or chain ID is not 31337')
            env = self.env.copy()
            env.update(TEST_DATABASE_URL=self.db, DATABASE_URL=self.db, CONTRACT_TEST_RPC=rpc)
            return self.run(p, 'live contract and API tests', [self.uv, 'run', '--locked', 'pytest', '-q', 'tests/test_live_contract.py'], cwd, env, True)
        except OSError:
            return self.record(p, 'live contract and API tests', 'blocked', 'managed node could not start')
        finally:
            if proc is not None and proc.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=5, check=False)
                else:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()

    def frontend(self):
        p, cwd = 'frontend', self.root / 'apps/flutter_app'
        build_cmd = ['build', 'web', '--no-pub']
        if getattr(self.args, 'chain_id', None) is not None:
            build_cmd.append(f'--dart-define=CHAIN_ID={self.args.chain_id}')
        if getattr(self.args, 'api_base_url', ''):
            build_cmd.append(f'--dart-define=API_BASE_URL={self.args.api_base_url}')
        commands = [('dependency lock', ['pub', 'get', '--enforce-lockfile']),
                    ('analyze', ['analyze', '--no-pub']), ('tests', ['test', '--no-pub', '--reporter', 'expanded']),
                    ('web build', build_cmd)]
        ok = self.run(p, commands[0][0], self.flutter + commands[0][1], cwd)
        checks = [ok]
        for name, cmd in commands[1:]:
            checks.append(self.run(p, name, self.flutter + cmd, cwd, forbid_skips=(name == 'tests')) if ok else self.record(p, name, 'blocked', 'dependency lock failed'))
        return all(checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--phase', choices=('all', *PHASES), default='all')
    parser.add_argument('--database-url-env', default='TEST_DATABASE_URL', help='name of env var containing a dedicated test database URL')
    parser.add_argument('--rpc-url', default='')
    parser.add_argument('--start-local-evm', action='store_true')
    parser.add_argument('--node-executable', default='node')
    parser.add_argument('--timeout', type=int, default=600, help='seconds per subprocess')
    parser.add_argument('--retries', type=int, default=0, help='retry failed subprocesses this many times')
    parser.add_argument('--chain-id', type=int, default=None, help='optional CHAIN_ID dart-define for flutter build web')
    parser.add_argument('--api-base-url', default='', help='optional API_BASE_URL dart-define for flutter build web')
    parser.add_argument('--output-dir', type=Path, default=Path('validation-results'))
    args = parser.parse_args()
    if args.timeout < 1 or args.retries < 0:
        parser.error('timeout must be positive and retries nonnegative')
    runner = Runner(args)
    selected = PHASES if args.phase == 'all' else (args.phase,)
    build_ok = False
    if 'contracts' in selected:
        build_ok = runner.contracts()
    if 'backend' in selected:
        runner.backend()
    if 'integration' in selected:
        if 'contracts' not in selected:
            node_ok = runner.run('integration', 'Node 24 version', [runner.node, '-e', "if (process.versions.node.split('.')[0] !== '24') process.exit(1)"], runner.root / 'contracts')
            build_ok = runner.run('integration', 'contract build', [runner.node, runner.hardhat, 'build'], runner.root / 'contracts') if node_ok else runner.record('integration', 'contract build', 'blocked', 'Node 24 unavailable')
        runner.integration(build_ok)
    if 'frontend' in selected:
        runner.frontend()
    success = bool(runner.results) and all(x['status'] == 'pass' for x in runner.results)
    for phase in PHASES:
        if phase not in selected:
            runner.record(phase, 'phase', 'skipped', 'not selected')
    report = dict(timestamp_utc=dt.datetime.now(dt.timezone.utc).isoformat(), phase=args.phase,
                  status='pass' if success else 'fail', results=runner.results)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    lines = ['# System validation', '', f"Overall: **{report['status']}**", f"UTC: {report['timestamp_utc']}", '',
             '| Phase | Check | Status | Seconds | Attempts | Detail |', '|---|---|---|---:|---:|---|']
    lines += [f"| {r['phase']} | {r['name']} | {r['status']} | {r['seconds']} | {r['attempts']} | {r['detail']} |" for r in runner.results]
    (args.output_dir / 'report.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
