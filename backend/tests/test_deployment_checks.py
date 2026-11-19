import pytest
from alembic import command
from alembic.config import Config
from eth_utils import function_signature_to_4byte_selector
from pydantic import ValidationError
from sqlalchemy import text
from web3 import Web3

from app.core.config import Deployment
from tests.fake_rpc import TOKEN


@pytest.mark.parametrize(
    ("mode", "adapter", "valid"),
    [
        ("MOCK", None, True),
        ("DISABLED", None, True),
        ("MOCK", "0x" + "55" * 20, True),
        ("DISABLED", "0x" + "00" * 20, True),
        ("MOCK", "0x" + "00" * 20, False),
        ("DISABLED", "0x" + "55" * 20, False),
    ],
)
def test_manifest_adapter_matches_mode_and_keeps_legacy_compatible(
    harness, mode, adapter, valid
):
    _, _, vault, _ = harness
    manifest = vault.deployment.model_dump()
    manifest.update(yield_mode=mode, adapter_address=adapter)
    if valid:
        assert Deployment.model_validate(manifest).yield_mode == mode
    else:
        with pytest.raises(
            ValidationError, match="adapter address must match yield mode"
        ):
            Deployment.model_validate(manifest)


def test_migration_head_matches_models(harness):
    command.check(Config("alembic.ini"))


def test_readiness_rejects_a_missing_deployment(harness, tmp_path):
    client, app, _, _ = harness
    app.state.vault = None
    app.state.settings.deployment_file = tmp_path / "missing.json"
    assert client.get("/health").status_code == 200
    response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "CONFIG_MISMATCH"


def test_readiness_checks_exported_runtime_fingerprint(harness):
    client, _, vault, _ = harness
    vault.deployment.vault_code_hash = "0x" + "00" * 32
    response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "CONFIG_MISMATCH"
    vault.deployment.vault_code_hash = Web3.to_hex(Web3.keccak(bytes.fromhex("6001")))
    assert client.get("/ready").status_code == 200


@pytest.mark.parametrize("revision", ["0001", "0002", "unknown", None])
def test_readiness_rejects_database_revision_drift(harness, revision):
    client, app, _, _ = harness
    with app.state.engine.begin() as connection:
        connection.execute(text("DELETE FROM alembic_version"))
        if revision is not None:
            connection.execute(
                text("INSERT INTO alembic_version VALUES (:revision)"),
                {"revision": revision},
            )
    assert client.get("/health").status_code == 200
    response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "DATABASE_UNAVAILABLE"


@pytest.mark.parametrize(
    ("signature", "value", "manifest"),
    [
        ("paymentToken()", "0x" + "99" * 20, {}),
        ("adapter()", "0x" + "00" * 20, {}),
        ("adapter()", "0x" + "55" * 20, {"yield_mode": "DISABLED"}),
        ("adapter()", "0x" + "99" * 20, {"adapter_address": "0x" + "55" * 20}),
        ("treasury()", "0x" + "99" * 20, {"treasury_address": "0x" + "66" * 20}),
    ],
)
def test_readiness_rejects_vault_token_or_yield_mode_mismatch(
    harness, monkeypatch, signature, value, manifest
):
    client, _, vault, rpc = harness
    vault.deployment = vault.deployment.model_copy(update=manifest)
    selector = "0x" + function_signature_to_4byte_selector(signature).hex()

    def request(method, params):
        if method == "eth_call" and params[0]["data"] == selector:
            return {
                "jsonrpc": "2.0",
                "id": 1,
                "result": "0x" + rpc.codec.encode(["address"], [value]).hex(),
            }
        return rpc.request(method, params)

    monkeypatch.setattr(vault.web3.provider, "make_request", request)
    assert vault.deployment.token.address == TOKEN
    response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "CONFIG_MISMATCH"
