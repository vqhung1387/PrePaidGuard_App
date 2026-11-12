from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.db import get_db
from app.core.errors import ApiError, config_error
from app.models.entities import AuthSession, Merchant, User
from app.schemas.api import UserResponse
from app.schemas.types import utcnow

Db = Annotated[Session, Depends(get_db)]
bearer = HTTPBearer(auto_error=False)


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


Config = Annotated[Settings, Depends(get_settings)]


def secret(settings: Settings) -> str:
    if settings.access_token_secret is None:
        raise config_error()
    return settings.access_token_secret.get_secret_value()


@dataclass(frozen=True)
class Principal:
    user: User
    session: AuthSession


def unauthorized(code: str = "UNAUTHORIZED") -> ApiError:
    return ApiError(
        401, code, "Cần đăng nhập bằng ví.", headers={"WWW-Authenticate": "Bearer"}
    )


def current_user(
    db: Db,
    settings: Config,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Security(bearer)],
) -> Principal:
    if credentials is None:
        raise unauthorized()
    try:
        claims = jwt.decode(
            credentials.credentials,
            secret(settings),
            algorithms=["HS256"],
            issuer=settings.auth_uri,
            audience="prepaidguard-api",
            options={"require": ["exp", "iat", "sub", "sid", "wallet", "chain_id"]},
        )
        user_id, session_id = UUID(claims["sub"]), UUID(claims["sid"])
    except jwt.ExpiredSignatureError:
        raise unauthorized("TOKEN_EXPIRED") from None
    except (jwt.InvalidTokenError, ValueError, TypeError, AttributeError):
        raise unauthorized() from None
    if claims["chain_id"] != settings.chain_id:
        raise unauthorized()
    auth_session = db.get(AuthSession, session_id)
    if (
        auth_session is None
        or auth_session.user_id != user_id
        or auth_session.chain_id != settings.chain_id
        or auth_session.revoked_at is not None
        or auth_session.expires_at <= utcnow()
    ):
        raise unauthorized()
    user = db.get(User, user_id)
    if user is None or user.wallet_address != claims["wallet"]:
        raise unauthorized()
    return Principal(user, auth_session)


Current = Annotated[Principal, Depends(current_user)]


def merchant_for(db: Session, user_id: UUID) -> Merchant | None:
    return db.scalar(select(Merchant).where(Merchant.owner_user_id == user_id))


def require_merchant(db: Db, principal: Current) -> Merchant:
    merchant = merchant_for(db, principal.user.id)
    if merchant is None:
        raise ApiError(403, "MERCHANT_REQUIRED", "Ví chưa có hồ sơ cơ sở.")
    return merchant


CurrentMerchant = Annotated[Merchant, Depends(require_merchant)]


def user_response(db: Session, user: User) -> UserResponse:
    return UserResponse(
        id=user.id,
        wallet_address=user.wallet_address,
        display_name=user.display_name,
        is_merchant=merchant_for(db, user.id) is not None,
        created_at=user.created_at,
    )
