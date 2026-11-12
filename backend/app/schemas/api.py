from datetime import datetime
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    TypeAdapter,
    model_validator,
)

from app.core.config import TokenConfig
from app.schemas.types import Address, ChainId, Hash32, Signature, UintOut, UintString

Name = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)
]
Description = Annotated[str, StringConstraints(max_length=2000)]
Location = Annotated[str, StringConstraints(max_length=300)]
DisplayName = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
]
Duration = Annotated[int, Field(strict=True, gt=0, le=2**63 - 1)]
Periods = Annotated[int, Field(strict=True, ge=1, le=120)]
SubscriptionStatus = Literal["ACTIVE", "COMPLETED", "REFUNDED"]
Action = Literal["CREATE_PLAN", "SUBSCRIBE", "CHECK_IN", "REFUND"]
EventName = Literal["PLAN_CREATED", "SUBSCRIBED", "PERIOD_RELEASED", "REFUNDED"]


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Output(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Health(Output):
    status: Literal["ok", "ready"]


class ConfigResponse(Output):
    environment: Literal["local", "demo"]
    deployment_id: str
    chain_id: ChainId
    chain_name: str
    rpc_url: str
    explorer_url: str
    vault_address: Address
    token: TokenConfig
    abi_version: str
    yield_mode: Literal["MOCK", "DISABLED"]
    check_in_ttl_seconds: Literal[900] = 900
    supported_wallet_kind: Literal["EOA"] = "EOA"
    auth_domain: str
    auth_uri: str


class ChallengeRequest(Input):
    wallet_address: Address
    chain_id: Annotated[ChainId, Field(strict=True)]


class ChallengeResponse(Output):
    challenge_id: UUID
    message: str
    expires_at: datetime


class VerifyRequest(Input):
    challenge_id: UUID
    signature: Signature


class UserResponse(Output):
    id: UUID
    wallet_address: Address
    display_name: str | None
    is_merchant: bool
    created_at: datetime


class UserUpdate(Input):
    display_name: DisplayName


class TokenResponse(Output):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_at: datetime
    user: UserResponse


class MerchantCreate(Input):
    business_name: Name
    description: Description = ""
    location_text: Location | None = None


class Patch(Input):
    @model_validator(mode="after")
    def require_fields(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("provide at least one field")
        if any(
            field != "location_text" and getattr(self, field) is None
            for field in self.model_fields_set
        ):
            raise ValueError("only location_text may be null")
        return self


class MerchantUpdate(Patch):
    business_name: Name | None = None
    description: Description | None = None
    location_text: Location | None = None


class MerchantResponse(Output):
    id: UUID
    owner_wallet: Address
    business_name: str
    description: str
    location_text: str | None
    created_at: datetime
    updated_at: datetime


class PlanTerms(Input):
    title: Name
    description: Description = ""
    price_per_period: UintString
    total_periods: Periods
    period_duration_seconds: Duration
    grace_period_seconds: Duration

    @model_validator(mode="after")
    def validate_terms(self) -> Self:
        if int(self.price_per_period) == 0:
            raise ValueError("price_per_period must be positive")
        UintStringAdapter.validate_python(
            str(int(self.price_per_period) * self.total_periods)
        )
        if self.period_duration_seconds + self.grace_period_seconds >= 2**63:
            raise ValueError("period and grace exceed supported timestamp range")
        return self


UintStringAdapter = TypeAdapter(UintString)


class DraftUpdate(Patch):
    title: Name | None = None
    description: Description | None = None
    price_per_period: UintString | None = None
    total_periods: Periods | None = None
    period_duration_seconds: Duration | None = None
    grace_period_seconds: Duration | None = None


class DraftResponse(Output):
    id: UUID
    merchant_id: UUID
    client_reference: Hash32
    title: str
    description: str
    token_address: Address
    price_per_period: UintOut
    total_periods: int
    period_duration_seconds: int
    grace_period_seconds: int
    total_price: UintOut
    state: Literal["DRAFT", "PUBLISHED"]
    chain_id: ChainId
    vault_address: Address
    onchain_plan_id: UintOut | None
    publication_tx_hash: Hash32 | None
    created_at: datetime
    updated_at: datetime


class SyncInfo(Output):
    block_number: UintOut
    block_hash: Hash32
    block_timestamp: datetime
    synced_at: datetime
    source: Literal["LIVE", "PROJECTION"]


class PlanResponse(Output):
    plan_id: UintOut
    chain_id: ChainId
    vault_address: Address
    merchant_address: Address
    merchant: MerchantResponse | None
    title: str
    description: str
    token: TokenConfig
    price_per_period: UintOut
    total_periods: int
    period_duration_seconds: int
    grace_period_seconds: int
    total_price: UintOut
    sync: SyncInfo


class YieldSummary(Output):
    mode: Literal["MOCK", "DISABLED"]
    estimated_unclaimed: UintOut | None
    paid_merchant: UintOut
    paid_subscriber: UintOut
    paid_platform: UintOut


class SubscriptionResponse(Output):
    subscription_id: UintOut
    plan_id: UintOut
    chain_id: ChainId
    vault_address: Address
    merchant_address: Address
    subscriber_address: Address
    token: TokenConfig
    initial_principal: UintOut
    remaining_principal: UintOut
    principal_released: UintOut
    principal_refunded: UintOut
    total_periods: int
    completed_periods: int
    next_period_index: UintOut | None
    started_at: datetime
    next_release_at: datetime | None
    refund_available_at: datetime | None
    nonce: UintOut
    status: SubscriptionStatus
    yield_summary: YieldSummary
    sync: SyncInfo


class EligibilityResponse(Output):
    subscription_id: UintOut
    status: SubscriptionStatus
    can_check_in: bool
    can_refund: bool
    next_period_index: UintOut | None
    nonce: UintOut
    next_release_at: datetime | None
    refund_available_at: datetime | None
    reasons: list[Literal["TOO_EARLY", "REFUND_WINDOW_OPEN", "TERMINAL_STATE", "READY"]]
    sync: SyncInfo


class EventResponse(Output):
    id: UUID
    event_name: EventName
    plan_id: UintOut
    subscription_id: UintOut | None
    tx_hash: Hash32
    log_index: int
    block_number: UintOut
    block_timestamp: datetime
    payload: dict[str, str | bool]
    explorer_url: str


class TransactionHash(Input):
    tx_hash: Hash32


class CreatePlanTransaction(TransactionHash):
    action: Literal["CREATE_PLAN"]
    plan_draft_id: UUID


class SubscribeTransaction(TransactionHash):
    action: Literal["SUBSCRIBE"]
    plan_id: UintString


class SubscriptionTransaction(TransactionHash):
    action: Literal["CHECK_IN", "REFUND"]
    subscription_id: UintString


TransactionSubmit = Annotated[
    CreatePlanTransaction | SubscribeTransaction | SubscriptionTransaction,
    Field(discriminator="action"),
]


class TransactionResponse(Output):
    tx_hash: Hash32
    chain_id: ChainId
    expected_action: Action
    status: Literal["SUBMITTED", "CONFIRMED", "REVERTED"]
    block_number: UintOut | None
    failure_code: str | None
    checked_at: datetime | None
    explorer_url: str
    event_ids: list[UUID]


class Page[T](Output):
    items: list[T]
    next_cursor: str | None
