from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import TypeDecorator

from app.schemas.types import UINT_MAX, utcnow


class UInt256(TypeDecorator):
    impl = Numeric(78, 0)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None and (type(value) is not int or not 0 <= value <= UINT_MAX):
            raise ValueError("expected a uint256 integer")
        return value

    def process_result_value(self, value, dialect):
        return int(value) if value is not None else None


def uint_checks(*columns: str) -> tuple[CheckConstraint, ...]:
    return tuple(
        CheckConstraint(f"{col} BETWEEN 0 AND {UINT_MAX}", name=f"ck_{col}_uint256")
        for col in columns
    )


class Base(DeclarativeBase):
    pass


class Identity:
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)


class Timestamps:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class User(Identity, Timestamps, Base):
    __tablename__ = "users"
    wallet_address: Mapped[str] = mapped_column(String(42), unique=True)
    display_name: Mapped[str | None] = mapped_column(String(80))


class AuthChallenge(Identity, Base):
    __tablename__ = "auth_challenges"
    wallet_address: Mapped[str] = mapped_column(String(42))
    source_ip: Mapped[str] = mapped_column(String(45))
    chain_id: Mapped[int] = mapped_column(BigInteger)
    nonce: Mapped[str] = mapped_column(String(64), unique=True)
    message: Mapped[str] = mapped_column(Text)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        Index("ix_challenge_wallet_time", "wallet_address", "issued_at"),
        Index("ix_challenge_ip_time", "source_ip", "issued_at"),
    )


class AuthSession(Identity, Base):
    __tablename__ = "auth_sessions"
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    chain_id: Mapped[int] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Merchant(Identity, Timestamps, Base):
    __tablename__ = "merchants"
    owner_user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), unique=True)
    business_name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(2000))
    location_text: Mapped[str | None] = mapped_column(String(300))


class VaultScope:
    chain_id: Mapped[int] = mapped_column(BigInteger)
    vault_address: Mapped[str] = mapped_column(String(42))


class PlanDraft(Identity, Timestamps, VaultScope, Base):
    __tablename__ = "plan_drafts"
    merchant_id: Mapped[UUID] = mapped_column(ForeignKey("merchants.id"), index=True)
    client_reference: Mapped[str] = mapped_column(String(66), unique=True)
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(2000))
    token_address: Mapped[str] = mapped_column(String(42))
    price_per_period: Mapped[int] = mapped_column(UInt256)
    total_periods: Mapped[int]
    period_duration_seconds: Mapped[int] = mapped_column(BigInteger)
    grace_period_seconds: Mapped[int] = mapped_column(BigInteger)
    state: Mapped[str] = mapped_column(String(9), default="DRAFT")
    onchain_plan_id: Mapped[int | None] = mapped_column(UInt256)
    publication_tx_hash: Mapped[str | None] = mapped_column(String(66))
    __table_args__ = (
        UniqueConstraint(
            "chain_id", "vault_address", "onchain_plan_id", name="uq_published_plan"
        ),
        Index("ix_draft_merchant_state", "merchant_id", "state"),
        *uint_checks("price_per_period", "onchain_plan_id"),
        CheckConstraint(
            f"price_per_period > 0 AND total_periods BETWEEN 1 AND 120 "
            f"AND price_per_period * total_periods <= {UINT_MAX} "
            "AND period_duration_seconds > 0 AND grace_period_seconds > 0",
            name="ck_plan_terms",
        ),
        CheckConstraint(
            "(state = 'DRAFT' AND onchain_plan_id IS NULL AND publication_tx_hash IS NULL) OR "
            "(state = 'PUBLISHED' AND onchain_plan_id IS NOT NULL AND publication_tx_hash IS NOT NULL)",
            name="ck_draft_state",
        ),
    )

    @property
    def total_price(self) -> int:
        return self.price_per_period * self.total_periods


class SubscriptionSnapshot(Identity, VaultScope, Base):
    __tablename__ = "subscription_snapshots"
    subscription_id: Mapped[int] = mapped_column(UInt256)
    plan_id: Mapped[int] = mapped_column(UInt256)
    merchant_address: Mapped[str] = mapped_column(String(42))
    subscriber_address: Mapped[str] = mapped_column(String(42))
    price_per_period: Mapped[int] = mapped_column(UInt256)
    initial_principal: Mapped[int] = mapped_column(UInt256)
    remaining_principal: Mapped[int] = mapped_column(UInt256)
    total_periods: Mapped[int]
    completed_periods: Mapped[int]
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    next_release_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    refund_available_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    nonce: Mapped[int] = mapped_column(UInt256)
    status: Mapped[str] = mapped_column(String(9))
    principal_released: Mapped[int] = mapped_column(UInt256)
    principal_refunded: Mapped[int] = mapped_column(UInt256)
    yield_paid_merchant: Mapped[int] = mapped_column(UInt256)
    yield_paid_subscriber: Mapped[int] = mapped_column(UInt256)
    yield_paid_platform: Mapped[int] = mapped_column(UInt256)
    synced_block_number: Mapped[int] = mapped_column(UInt256)
    synced_block_hash: Mapped[str] = mapped_column(String(66))
    synced_block_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    __table_args__ = (
        UniqueConstraint(
            "chain_id", "vault_address", "subscription_id", name="uq_subscription"
        ),
        Index("ix_sub_subscriber", "chain_id", "vault_address", "subscriber_address"),
        Index("ix_sub_merchant", "chain_id", "vault_address", "merchant_address"),
        *uint_checks(
            "subscription_id",
            "plan_id",
            "price_per_period",
            "initial_principal",
            "remaining_principal",
            "nonce",
            "principal_released",
            "principal_refunded",
            "yield_paid_merchant",
            "yield_paid_subscriber",
            "yield_paid_platform",
            "synced_block_number",
        ),
        CheckConstraint(
            "status IN ('ACTIVE','COMPLETED','REFUNDED') AND total_periods BETWEEN 1 AND 120 "
            "AND completed_periods BETWEEN 0 AND total_periods AND "
            "initial_principal = remaining_principal + principal_released + principal_refunded",
            name="ck_subscription_state",
        ),
    )


class TransactionRecord(Identity, VaultScope, Base):
    __tablename__ = "transactions"
    submitted_by_user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id"), index=True
    )
    tx_hash: Mapped[str] = mapped_column(String(66))
    expected_action: Mapped[str] = mapped_column(String(11))
    plan_draft_id: Mapped[UUID | None] = mapped_column(ForeignKey("plan_drafts.id"))
    subscription_id: Mapped[int | None] = mapped_column(UInt256)
    plan_id: Mapped[int | None] = mapped_column(UInt256)
    status: Mapped[str] = mapped_column(String(9), default="SUBMITTED")
    block_number: Mapped[int | None] = mapped_column(UInt256)
    block_hash: Mapped[str | None] = mapped_column(String(66))
    failure_code: Mapped[str | None] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        UniqueConstraint("chain_id", "tx_hash", name="uq_transaction_hash"),
        *uint_checks("subscription_id", "plan_id", "block_number"),
        CheckConstraint(
            "status IN ('SUBMITTED','CONFIRMED','REVERTED')", name="ck_tx_status"
        ),
        CheckConstraint(
            "(expected_action = 'CREATE_PLAN' AND plan_draft_id IS NOT NULL AND plan_id IS NULL "
            "AND subscription_id IS NULL) OR "
            "(expected_action = 'SUBSCRIBE' AND plan_id IS NOT NULL AND plan_draft_id IS NULL "
            "AND subscription_id IS NULL) OR "
            "(expected_action IN ('CHECK_IN','REFUND') AND subscription_id IS NOT NULL "
            "AND plan_id IS NULL AND plan_draft_id IS NULL)",
            name="ck_tx_action_reference",
        ),
    )


class EventRecord(Identity, VaultScope, Base):
    __tablename__ = "events"
    tx_hash: Mapped[str] = mapped_column(String(66))
    log_index: Mapped[int] = mapped_column(Integer)
    block_number: Mapped[int] = mapped_column(UInt256)
    block_hash: Mapped[str] = mapped_column(String(66))
    block_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    event_name: Mapped[str] = mapped_column(String(16))
    plan_id: Mapped[int] = mapped_column(UInt256)
    subscription_id: Mapped[int | None] = mapped_column(UInt256)
    merchant_address: Mapped[str] = mapped_column(String(42))
    subscriber_address: Mapped[str | None] = mapped_column(String(42))
    payload: Mapped[dict] = mapped_column(JSONB)
    __table_args__ = (
        UniqueConstraint(
            "chain_id", "vault_address", "tx_hash", "log_index", name="uq_event_log"
        ),
        Index(
            "ix_event_subscription",
            "chain_id",
            "vault_address",
            "subscription_id",
            "block_number",
        ),
        Index("ix_event_plan", "chain_id", "vault_address", "event_name", "plan_id"),
        *uint_checks("block_number", "plan_id", "subscription_id"),
        CheckConstraint(
            "log_index >= 0 AND ((event_name = 'PLAN_CREATED' AND subscription_id IS NULL "
            "AND subscriber_address IS NULL) OR (event_name IN ('SUBSCRIBED','PERIOD_RELEASED','REFUNDED') "
            "AND subscription_id IS NOT NULL AND subscriber_address IS NOT NULL))",
            name="ck_event_kind",
        ),
    )


class SyncCursor(Base):
    __tablename__ = "sync_cursors"
    chain_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    vault_address: Mapped[str] = mapped_column(String(42), primary_key=True)
    last_processed_block: Mapped[int] = mapped_column(UInt256)
    last_processed_block_hash: Mapped[str] = mapped_column(String(66))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )
    __table_args__ = uint_checks("last_processed_block")
