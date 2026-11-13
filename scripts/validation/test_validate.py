import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('validate', Path(__file__).with_name('validate.py'))
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


class ValidationTests(unittest.TestCase):
    def test_rpc_restrictions(self):
        self.assertTrue(v.local_rpc('http://127.0.0.1:8545'))
        for url in ('https://example.com', 'http://127.0.0.1.evil:8545',
                    'http://user:secret@localhost:8545', 'http://localhost:8545/?token=secret'):
            self.assertFalse(v.local_rpc(url))

    def test_schema_scoping(self):
        scoped = v.schema_url('postgresql+psycopg://u:p@localhost/test', 'pp_validate_a')
        self.assertIn('options=-csearch_path%3Dpp_validate_a', scoped)
        with self.assertRaises(ValueError):
            v.schema_url('postgresql://u:p@localhost/test?options=bad', 'pp_validate_a')

    def test_missing_database_is_blocked_and_report_is_nonzero(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ)
            env.pop('VALIDATION_TEST_NO_DATABASE', None)
            result = subprocess.run([sys.executable, str(Path(v.__file__)), '--phase', 'backend',
                '--repo-root', tmp, '--database-url-env', 'VALIDATION_TEST_NO_DATABASE',
                '--output-dir', str(Path(tmp) / 'out'), '--timeout', '1'], env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            report = __import__('json').loads((Path(tmp) / 'out/report.json').read_text())
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(report['status'], 'fail')
            self.assertTrue(any(r['status'] == 'blocked' for r in report['results']))

    def test_timeout_and_secret_output_are_not_reported(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_NO_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 1
            retries = 0
        runner = v.Runner(Args())
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(runner.run('test', 'timeout', [sys.executable, '-c',
                "import time; print('secret-token', flush=True); time.sleep(3)"], tmp))
            self.assertFalse(runner.run('test', 'failure', [sys.executable, '-c',
                "print('secret-token'); raise SystemExit(2)"], tmp))
        self.assertNotIn('secret-token', str(runner.results))
        self.assertIn('timed out', runner.results[0]['detail'])

    def test_failed_schema_setup_still_attempts_owned_cleanup(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 3
            retries = 0
        calls = []
        with patch.dict(os.environ, {'VALIDATION_TEST_DATABASE': 'postgresql://u:p@localhost/test'}):
            runner = v.Runner(Args())
        def fake_run(phase, name, cmd, cwd, env=None, forbid_skips=False):
            calls.append((name, cmd, dict(env or {})))
            return runner.record(phase, name, 'fail' if name == 'migration schema setup' else 'pass')
        with patch.object(runner, 'run', side_effect=fake_run):
            self.assertFalse(runner.backend())
        cleanup = next(c for c in calls if c[0] == 'migration schema cleanup')
        self.assertIn('DROP SCHEMA IF EXISTS', cleanup[1][-1])
        self.assertIn('CASCADE', cleanup[1][-1])
        self.assertRegex(cleanup[2]['VALIDATION_SCHEMA'], r'^pp_validate_[a-f0-9]{32}$')

    def test_timeout_kills_child_process(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_NO_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 1
            retries = 0
        runner = v.Runner(Args())
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / 'marker'
            child = "import pathlib,time; time.sleep(3); pathlib.Path(" + repr(str(marker)) + ").write_text('survived')"
            parent = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c'," + repr(child) + "]); time.sleep(10)"
            start = time.monotonic()
            self.assertFalse(runner.run('test', 'child timeout', [sys.executable, '-c', parent], tmp))
            self.assertLess(time.monotonic() - start, 3)
            time.sleep(3)
            self.assertFalse(marker.exists())

    def test_retries_record_attempts(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_NO_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 3
            retries = 1
        runner = v.Runner(Args())
        with patch.object(v, 'run_process', side_effect=[
            subprocess.CompletedProcess([], 1, b'private'),
            subprocess.CompletedProcess([], 0, b'')
        ]):
            self.assertTrue(runner.run('test', 'retry', ['ignored'], '.'))
        self.assertEqual(runner.results[0]['attempts'], 2)
        self.assertNotIn('private', str(runner.results))

    def test_mocha_pending_and_financial_pending_text(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_NO_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 3
            retries = 0
        runner = v.Runner(Args())
        with patch.object(v, 'run_process', side_effect=[
            subprocess.CompletedProcess([], 0, b'5 passing (1s)\n  1 pending\n'),
            subprocess.CompletedProcess([], 0, b'transaction pending\n5 passing (1s)\n')
        ]):
            self.assertFalse(runner.run('test', 'mocha pending', ['ignored'], '.', forbid_skips=True))
            self.assertTrue(runner.run('test', 'financial state', ['ignored'], '.', forbid_skips=True))

    def test_skips_fail(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_NO_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 3
            retries = 0
        runner = v.Runner(Args())
        self.assertFalse(runner.run('test', 'skips', [sys.executable, '-c',
            "print('1 passed, 1 skipped')"], '.', forbid_skips=True))
        self.assertTrue(runner.run('test', 'flutter title mentioning skipped', [sys.executable, '-c',
            "print('00:01 +1: old QR skipped replay cleanly')"], '.', forbid_skips=True))

    def test_frontend_optional_dart_defines(self):
        class Args:
            repo_root = Path('.')
            database_url_env = 'VALIDATION_TEST_NO_DATABASE'
            rpc_url = ''
            node_executable = sys.executable
            timeout = 3
            retries = 0
            chain_id = 31337
            api_base_url = 'http://127.0.0.1:18000'
        runner = v.Runner(Args())
        seen = []
        def fake_run(phase, name, cmd, cwd, env=None, forbid_skips=False):
            seen.append((name, cmd))
            return runner.record(phase, name, 'pass')
        with patch.object(runner, 'run', side_effect=fake_run):
            self.assertTrue(runner.frontend())
        build_cmd = next(cmd for name, cmd in seen if name == 'web build')
        self.assertIn('--dart-define=CHAIN_ID=31337', build_cmd)
        self.assertIn('--dart-define=API_BASE_URL=http://127.0.0.1:18000', build_cmd)


if __name__ == '__main__':
    unittest.main()
