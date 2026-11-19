import json
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from app.blockchain.vault import Vault
from app.core.config import Settings
from app.main import create_app
from tests.fake_rpc import ABI, TOKEN, VAULT, FakeRpc


@pytest.fixture
def harness(tmp_path, monkeypatch):
    import os

    db_url = os.environ.get("TEST_DATABASE_URL")
    if db_url is None:
        pytest.skip("Set TEST_DATABASE_URL to a PostgreSQL test database")
    url = make_url(db_url)
    schema = "pp_test_" + uuid4().hex
    admin = create_engine(url)
    with admin.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    try:
        test_url = url.update_query_dict({"options": f"-csearch_path={schema}"})
        monkeypatch.setenv(
            "DATABASE_URL", test_url.render_as_string(hide_password=False)
        )
        command.upgrade(Config("alembic.ini"), "head")
        deployment = tmp_path / "deployment.json"
        deployment.write_text(
            json.dumps(
                {
                    "deployment_id": "local-fixture",
                    "chain_id": 43113,
                    "chain_name": "Fixture",
                    "public_rpc_url": "https://public.example.test",
                    "explorer_url": "https://explorer.example.test",
                    "vault_address": VAULT,
                    "token": {"address": TOKEN},
                    "abi_version": "fixture",
                    "deployment_block": 100,
                    "yield_mode": "MOCK",
                    "confirmations": 2,
                    "subscription_status_codes": {
                        "active": 0,
                        "completed": 1,
                        "refunded": 2,
                    },
                }
            ),
            encoding="utf-8",
        )
        abi = tmp_path / "vault.json"
        abi.write_text(json.dumps(ABI), encoding="utf-8")
        settings = Settings(
            access_token_secret="fixture-only-" * 3,
            deployment_file=deployment,
            abi_file=abi,
            rpc_url="https://private.example.test/secret",
            sync_batch_size=8,
            sync_overlap=2,
        )
        vault = Vault(settings)
        rpc = FakeRpc(vault)
        monkeypatch.setattr(vault.web3.provider, "make_request", rpc.request)
        app = create_app(settings, vault)
        with TestClient(app) as client:
            yield client, app, vault, rpc
    finally:
        with admin.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin.dispose()
