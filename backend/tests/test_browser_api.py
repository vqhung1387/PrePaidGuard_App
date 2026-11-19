import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.core.config import Settings
from app.main import create_app


def test_flutter_web_can_send_bearer_requests_and_read_api_errors():
    origin = "http://localhost:8080"
    app = create_app(
        Settings(
            _env_file=None, cors_origins=[origin], deployment_file=None, abi_file=None
        )
    )
    preflight = {
        "Access-Control-Request-Method": "PATCH",
        "Access-Control-Request-Headers": "authorization,content-type",
    }
    with TestClient(app) as client:
        health = client.get("/health", headers={"Origin": origin})
        assert health.json() == {"status": "ok"}
        assert health.headers["Access-Control-Allow-Origin"] == origin

        config = client.get("/api/v1/config", headers={"Origin": origin})
        assert config.status_code == 503
        assert config.json()["error"]["code"] == "CONFIG_MISMATCH"
        assert config.headers["Access-Control-Allow-Origin"] == origin

        allowed = client.options(
            "/api/v1/merchants/unused", headers={"Origin": origin, **preflight}
        )
        assert allowed.status_code == 200
        assert allowed.headers["Access-Control-Allow-Origin"] == origin
        assert (
            "authorization" in allowed.headers["Access-Control-Allow-Headers"].lower()
        )

        denied = client.options(
            "/api/v1/merchants/unused",
            headers={"Origin": "http://localhost:8081", **preflight},
        )
        assert denied.status_code == 400
        assert "Access-Control-Allow-Origin" not in denied.headers

        response = client.get("/api/v1/me", headers={"Origin": origin})
        assert response.status_code == 401
        assert response.headers["Access-Control-Allow-Origin"] == origin
        exposed = response.headers["Access-Control-Expose-Headers"].lower().split(", ")
        assert {"x-request-id", "retry-after", "www-authenticate"} <= set(exposed)
        assert response.headers["WWW-Authenticate"] == "Bearer"
        assert (
            response.json()["error"]["request_id"] == response.headers["X-Request-ID"]
        )


@pytest.mark.parametrize(
    "origin", ["*", "https://example.com/", "https://user@example.com"]
)
def test_cors_rejects_invalid_origin_configuration(origin):
    with pytest.raises(ValidationError, match="CORS_ORIGINS"):
        Settings(_env_file=None, cors_origins=[origin])
