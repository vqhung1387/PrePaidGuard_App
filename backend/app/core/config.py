from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import BaseModel, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.schemas.types import Address, ChainId

BACKEND_DIR = Path(__file__).resolve().parents[2]


class TokenConfig(BaseModel):
    address: Address
    symbol: str = "mUSDC"
    decimals: Literal[6] = 6


class StatusCodes(BaseModel):
    active: int = Field(ge=0, le=255)
    completed: int = Field(ge=0, le=255)
    refunded: int = Field(ge=0, le=255)

    @model_validator(mode="after")
    def distinct(self):
        if len({self.active, self.completed, self.refunded}) != 3:
            raise ValueError("subscription status codes must be distinct")
        return self


class Deployment(BaseModel):
    deployment_id: str = Field(min_length=1)
    chain_id: ChainId
    chain_name: str
    public_rpc_url: str
    explorer_url: str
    vault_address: Address
    token: TokenConfig
    abi_version: str = Field(min_length=1)
    deployment_block: int = Field(ge=0)
    yield_mode: Literal["MOCK", "DISABLED"] = "DISABLED"
    confirmations: int = Field(default=1, ge=1)
    subscription_status_codes: StatusCodes

    @model_validator(mode="after")
    def public_urls(self):
        if self.vault_address == self.token.address or any(
            int(address, 16) == 0
            for address in (self.vault_address, self.token.address)
        ):
            raise ValueError(
                "deployment requires distinct nonzero Vault and token addresses"
            )
        for value in (self.public_rpc_url, self.explorer_url):
            url = urlsplit(value)
            if (
                url.scheme not in {"http", "https"}
                or not url.hostname
                or any((url.username, url.password, url.query, url.fragment))
            ):
                raise ValueError(
                    "public URLs must be HTTP(S) without credentials, query or fragment"
                )
        return self


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        env_ignore_empty=True,
        hide_input_in_errors=True,
        extra="ignore",
    )

    environment: Literal["local", "demo"] = "local"
    database_url: SecretStr = SecretStr("postgresql+psycopg://localhost/prepaidguard")
    rpc_url: SecretStr | None = None
    deployment_file: Path | None = None
    abi_file: Path | None = None
    chain_id: ChainId = 43113
    auth_domain: str = "localhost:8000"
    auth_uri: str = "http://localhost:8000"
    access_token_secret: SecretStr | None = None
    access_token_ttl_seconds: int = Field(default=3600, ge=1, le=3600)
    challenge_rate_limit: int = Field(default=10, ge=1)
    cors_origins: list[str] = Field(default_factory=list)
    rpc_timeout_seconds: float = Field(default=5, gt=0, le=30)
    sync_batch_size: int = Field(default=90, ge=1, le=2000)
    sync_overlap: int = Field(default=8, ge=0, le=100)
    sync_interval_seconds: int = Field(default=0, ge=0)

    @field_validator("cors_origins")
    @classmethod
    def validate_cors_origins(cls, origins: list[str]) -> list[str]:
        for origin in origins:
            url = urlsplit(origin)
            if (
                url.scheme not in {"http", "https"}
                or not url.hostname
                or url.username is not None
                or not origin.isascii()
                or any(char.isspace() or ord(char) < 32 for char in origin)
                or origin != f"{url.scheme}://{url.netloc}"
                or url.port == 0
            ):
                raise ValueError(
                    "CORS_ORIGINS must contain exact HTTP(S) origins without paths"
                )
        return origins

    @model_validator(mode="after")
    def validate_auth(self):
        uri = urlsplit(self.auth_uri)
        if (
            uri.netloc != self.auth_domain
            or not uri.hostname
            or uri.scheme not in {"https", "http"}
            or any((uri.username, uri.password, uri.fragment))
            or not self.auth_uri.isascii()
            or any(ord(c) <= 32 or ord(c) == 127 for c in self.auth_uri)
        ):
            raise ValueError(
                "AUTH_URI must be a valid HTTP(S) URI matching AUTH_DOMAIN"
            )
        if self.environment == "demo" and uri.scheme != "https":
            raise ValueError("demo AUTH_URI requires HTTPS")
        if (
            self.access_token_secret is not None
            and len(self.access_token_secret.get_secret_value().encode()) < 32
        ):
            raise ValueError("ACCESS_TOKEN_SECRET must contain at least 32 bytes")
        if self.environment == "demo" and self.access_token_secret is None:
            raise ValueError("demo requires ACCESS_TOKEN_SECRET")
        return self


def backend_path(path: Path) -> Path:
    return BACKEND_DIR / path
