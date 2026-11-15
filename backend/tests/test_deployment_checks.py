from alembic import command
from alembic.config import Config


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
