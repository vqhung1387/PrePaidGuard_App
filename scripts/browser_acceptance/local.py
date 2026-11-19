"""Own a disposable loopback EVM/API/web and an isolated PostgreSQL schema."""

import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlsplit
from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from web3 import Web3

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from scripts.validation.validate import chain_id, local_rpc, run_process, schema_url


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpc-url", default="http://127.0.0.1:18545")
    parser.add_argument("--browser")
    parser.add_argument("--node-executable", default="node")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--runner", default="run.py")
    args = parser.parse_args()
    if not local_rpc(args.rpc_url):
        parser.error("RPC must be a clean HTTP loopback origin")
    database = os.environ.get("TEST_DATABASE_URL", "")
    if not database:
        parser.error(
            "TEST_DATABASE_URL must identify a dedicated PostgreSQL test database"
        )
    root = Path(__file__).resolve().parents[2]
    out = (args.output_dir or root / "validation-results/browser").resolve()
    schema = "pp_browser_" + uuid4().hex
    scoped = schema_url(database, schema)
    parsed = urlsplit(args.rpc_url)
    rpc_port = parsed.port or 80
    for host, port in [
        (parsed.hostname, rpc_port),
        ("127.0.0.1", 18010),
        ("127.0.0.1", 18090),
    ]:
        with socket.socket() as probe:
            if probe.connect_ex((host, port)) == 0:
                raise SystemExit(
                    f"Port {port} is occupied; refusing to use another process"
                )
    out.mkdir(parents=True, exist_ok=True)
    children, logs = [], []
    created = False
    admin = create_engine(database, connect_args={"connect_timeout": 5})

    def start(name, cmd, cwd, env=None):
        log = (out / (name + ".log")).open("wb")
        logs.append(log)
        process = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        children.append(process)
        return process

    try:
        node = start(
            "evm",
            [
                args.node_executable,
                str(root / "contracts/node_modules/hardhat/dist/src/cli.js"),
                "node",
                "--hostname",
                parsed.hostname,
                "--port",
                str(rpc_port),
            ],
            root / "contracts",
        )
        stop = time.monotonic() + 30
        while chain_id(args.rpc_url) != 31337:
            if node.poll() is not None or time.monotonic() >= stop:
                raise RuntimeError("Owned local EVM did not become ready")
            time.sleep(0.2)
        w3 = Web3(Web3.HTTPProvider(args.rpc_url))
        accounts = w3.eth.accounts

        def deploy(name, source, values):
            artifact = json.loads(
                (
                    root / f"contracts/artifacts/contracts/{source}.sol/{name}.json"
                ).read_text()
            )
            factory = w3.eth.contract(
                abi=artifact["abi"], bytecode=artifact["bytecode"]
            )
            receipt = w3.eth.wait_for_transaction_receipt(
                factory.constructor(*values).transact({"from": accounts[0]})
            )
            if receipt.status != 1:
                raise RuntimeError("Local fixture deployment reverted")
            return w3.eth.contract(
                address=receipt.contractAddress, abi=artifact["abi"]
            ), receipt

        with admin.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
            created = True
        os.environ["DATABASE_URL"] = scoped
        os.chdir(root / "backend")
        command.upgrade(Config("alembic.ini"), "head")
        token, _ = deploy("MockUSDC", "mocks/MockUSDC", [accounts[0]])
        adapter, _ = deploy(
            "MockYieldAdapter", "mocks/MockYieldAdapter", [token.address, accounts[0]]
        )
        vault, receipt = deploy(
            "PrepaidVault",
            "PrepaidVault",
            [token.address, accounts[3], adapter.address],
        )
        for tx in [
            adapter.functions.bindVault(vault.address).transact({"from": accounts[0]}),
            token.functions.mint(accounts[2], 1_000_000_000).transact(
                {"from": accounts[0]}
            ),
        ]:
            if w3.eth.wait_for_transaction_receipt(tx).status != 1:
                raise RuntimeError("Local fixture funding reverted")
        manifest = out / "deployment.local.json"
        manifest.write_text(
            json.dumps(
                {
                    "deployment_id": "browser-" + vault.address.lower(),
                    "chain_id": 31337,
                    "chain_name": "Local",
                    "public_rpc_url": args.rpc_url,
                    "explorer_url": args.rpc_url,
                    "vault_address": vault.address,
                    "token": {"address": token.address},
                    "abi_version": "prepaidguard-1",
                    "deployment_block": receipt.blockNumber,
                    "yield_mode": "MOCK",
                    "confirmations": 1,
                    "subscription_status_codes": {
                        "active": 1,
                        "completed": 2,
                        "refunded": 3,
                    },
                }
            ),
            encoding="utf-8",
        )
        env = dict(
            os.environ,
            DATABASE_URL=scoped,
            RPC_URL=args.rpc_url,
            CHAIN_ID="31337",
            ABI_FILE=str(root / "shared/abi/PrepaidVault.json"),
            DEPLOYMENT_FILE=str(manifest),
            ACCESS_TOKEN_SECRET="isolated-browser-test-only-" * 3,
            ENVIRONMENT="local",
            AUTH_DOMAIN="127.0.0.1:18010",
            AUTH_URI="http://127.0.0.1:18010",
            CORS_ORIGINS='["http://127.0.0.1:18090"]',
            SYNC_INTERVAL_SECONDS="2",
            CHALLENGE_RATE_LIMIT="100",
        )
        api = start(
            "api",
            [
                sys.executable,
                "-m",
                "uvicorn",
                "app.main:app",
                "--host",
                "127.0.0.1",
                "--port",
                "18010",
            ],
            root / "backend",
            env,
        )
        start(
            "web",
            [
                sys.executable,
                "-m",
                "http.server",
                "18090",
                "--bind",
                "127.0.0.1",
                "--directory",
                str(root / "apps/flutter_app/build/web"),
            ],
            root,
        )
        stop = time.monotonic() + 45
        while True:
            if api.poll() is not None:
                raise RuntimeError("Owned API exited before readiness")
            try:
                with urllib.request.urlopen(
                    "http://127.0.0.1:18010/ready", timeout=2
                ) as response:
                    if response.status == 200:
                        break
            except OSError:
                pass
            if time.monotonic() >= stop:
                raise TimeoutError("Owned API did not become ready")
            time.sleep(0.2)
        print("Isolated EVM/API/web ready; running browser acceptance.", flush=True)
        cmd = [
            sys.executable,
            str(root / "scripts/browser_acceptance" / args.runner),
            "--app-url",
            "http://127.0.0.1:18090",
            "--api-url",
            "http://127.0.0.1:18010",
            "--rpc-url",
            args.rpc_url,
            "--inject-cache-failure",
            "--test-replacement",
            "--merchant-clock-skew",
            "-30",
            "--subscriber-clock-skew",
            "30",
            "--output-dir",
            str(out / "browser"),
        ]
        if args.browser:
            cmd += ["--browser", args.browser]
        result = run_process(cmd, root, env, 300)
        print(result.stdout.decode("utf-8", errors="replace"))
        return result.returncode
    finally:
        for process in reversed(children):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        for log in logs:
            log.close()
        if created:
            with admin.begin() as connection:
                connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
