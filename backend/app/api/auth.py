import secrets
from datetime import UTC, timedelta
from uuid import uuid4

import jwt
from eth_account import Account
from eth_account.messages import encode_defunct
from eth_keys.exceptions import BadSignature
from fastapi import APIRouter, Request
from sqlalchemy import func, select, update
from web3 import Web3

from app.api.dependencies import (
    Config,
    Current,
    Db,
    secret,
    unauthorized,
    user_response,
)
from app.core.db import lock
from app.core.errors import ApiError
from app.models.entities import AuthChallenge, AuthSession, User
from app.schemas.api import (
    ChallengeRequest,
    ChallengeResponse,
    TokenResponse,
    UserResponse,
    UserUpdate,
    VerifyRequest,
)
from app.schemas.types import utcnow

router = APIRouter(tags=["wallet authentication"])


def siwe_message(settings, challenge: AuthChallenge) -> str:
    issued = challenge.issued_at.astimezone(UTC).isoformat().replace("+00:00", "Z")
    expires = challenge.expires_at.astimezone(UTC).isoformat().replace("+00:00", "Z")
    return (
        f"{settings.auth_domain} wants you to sign in with your Ethereum account:\n"
        f"{Web3.to_checksum_address(challenge.wallet_address)}\n\n"
        "Sign in to PrePaidGuard. This request does not initiate a transaction.\n\n"
        f"URI: {settings.auth_uri}\nVersion: 1\nChain ID: {challenge.chain_id}\n"
        f"Nonce: {challenge.nonce}\nIssued At: {issued}\nExpiration Time: {expires}\n"
        f"Request ID: {challenge.id}"
    )


@router.post("/auth/challenge", status_code=201, response_model=ChallengeResponse)
def issue_challenge(body: ChallengeRequest, request: Request, db: Db, settings: Config):
    if body.chain_id != settings.chain_id:
        raise ApiError(400, "UNSUPPORTED_CHAIN", "Ví đang ở sai mạng.")
    if int(body.wallet_address, 16) == 0:
        raise ApiError(400, "UNSUPPORTED_WALLET", "Địa chỉ ví không được hỗ trợ.")
    secret(settings)
    ip = request.client.host if request.client else "unknown"
    lock(db, f"challenge:ip:{ip}")
    lock(db, f"challenge:wallet:{body.wallet_address}")
    now = utcnow().replace(microsecond=0)
    for condition in (
        AuthChallenge.source_ip == ip,
        AuthChallenge.wallet_address == body.wallet_address,
    ):
        count = db.scalar(
            select(func.count())
            .select_from(AuthChallenge)
            .where(condition, AuthChallenge.issued_at > now - timedelta(minutes=5))
        )
        if count >= settings.challenge_rate_limit:
            raise ApiError(
                429,
                "RATE_LIMITED",
                "Vui lòng thử lại sau.",
                headers={"Retry-After": "300"},
            )
    challenge = AuthChallenge(
        id=uuid4(),
        wallet_address=body.wallet_address,
        source_ip=ip,
        chain_id=body.chain_id,
        nonce=secrets.token_hex(16),
        issued_at=now,
        expires_at=now + timedelta(minutes=5),
    )
    challenge.message = siwe_message(settings, challenge)
    db.add(challenge)
    db.commit()
    return ChallengeResponse(
        challenge_id=challenge.id,
        message=challenge.message,
        expires_at=challenge.expires_at,
    )


@router.post("/auth/verify", response_model=TokenResponse)
def verify(body: VerifyRequest, db: Db, settings: Config):
    signing_secret = secret(settings)
    challenge = db.get(AuthChallenge, body.challenge_id)
    now = utcnow()
    if challenge is None or challenge.expires_at <= now:
        raise unauthorized("CHALLENGE_EXPIRED")
    if challenge.consumed_at is not None:
        raise unauthorized("CHALLENGE_USED")
    if (
        challenge.chain_id != settings.chain_id
        or challenge.issued_at > now
        or challenge.message != siwe_message(settings, challenge)
    ):
        raise unauthorized("INVALID_SIGNATURE")
    try:
        signer = Account.recover_message(
            encode_defunct(text=challenge.message), signature=body.signature
        ).lower()
    except (ValueError, TypeError, BadSignature):
        raise unauthorized("INVALID_SIGNATURE") from None
    if signer != challenge.wallet_address:
        raise unauthorized("INVALID_SIGNATURE")
    changed = db.scalar(
        update(AuthChallenge)
        .where(
            AuthChallenge.id == challenge.id,
            AuthChallenge.consumed_at.is_(None),
            AuthChallenge.expires_at > func.clock_timestamp(),
        )
        .values(consumed_at=func.clock_timestamp())
        .returning(AuthChallenge.id)
    )
    if changed is None:
        db.refresh(challenge)
        raise unauthorized(
            "CHALLENGE_USED" if challenge.consumed_at else "CHALLENGE_EXPIRED"
        )
    lock(db, f"auth:user:{signer}")
    user = db.scalar(select(User).where(User.wallet_address == signer))
    if user is None:
        user = User(wallet_address=signer)
        db.add(user)
        db.flush()
    issued = utcnow().replace(microsecond=0)
    session = AuthSession(
        user_id=user.id,
        chain_id=settings.chain_id,
        expires_at=issued + timedelta(seconds=settings.access_token_ttl_seconds),
    )
    db.add(session)
    db.flush()
    token = jwt.encode(
        {
            "sub": str(user.id),
            "sid": str(session.id),
            "wallet": signer,
            "chain_id": session.chain_id,
            "iat": issued,
            "exp": session.expires_at,
            "iss": settings.auth_uri,
            "aud": "prepaidguard-api",
        },
        signing_secret,
        algorithm="HS256",
    )
    result = TokenResponse(
        access_token=token, expires_at=session.expires_at, user=user_response(db, user)
    )
    db.commit()
    return result


@router.post("/auth/logout", status_code=204)
def logout(db: Db, principal: Current):
    principal.session.revoked_at = utcnow()
    db.commit()


@router.get("/me", response_model=UserResponse)
def me(db: Db, principal: Current):
    return user_response(db, principal.user)


@router.patch("/me", response_model=UserResponse)
def patch_me(body: UserUpdate, db: Db, principal: Current):
    principal.user.display_name = body.display_name
    db.commit()
    return user_response(db, principal.user)
