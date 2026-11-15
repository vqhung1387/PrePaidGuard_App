import os
import socket
import subprocess
import sys
from pathlib import Path

import pytest

RUNNER = Path(__file__).resolve().parents[2] / "scripts/browser_acceptance/local.py"


@pytest.mark.parametrize(
    "url",
    [
        "https://example.com",
        "http://user:secret@localhost:8545",
        "http://127.0.0.1:8545/?key=secret",
    ],
)
def test_browser_runner_refuses_nonlocal_or_credentialed_rpc(url):
    result = subprocess.run(
        [sys.executable, str(RUNNER), "--rpc-url", url],
        capture_output=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 2
    assert b"clean HTTP loopback origin" in result.stderr
    assert b"user:secret" not in result.stderr


def test_browser_runner_never_owns_an_existing_node():
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        env = dict(
            os.environ, TEST_DATABASE_URL="postgresql+psycopg://localhost/unused"
        )
        result = subprocess.run(
            [sys.executable, str(RUNNER), "--rpc-url", f"http://127.0.0.1:{port}"],
            capture_output=True,
            check=False,
            env=env,
            timeout=15,
        )
    assert result.returncode == 1
    assert b"refusing to use another process" in result.stderr
