from datetime import datetime

from fastapi import APIRouter
from sqlalchemy import select

from app.api.dependencies import Config, Current, CurrentMerchant, Db
from app.api.metadata import merchant_response
from app.api.system import Chain
from app.blockchain.vault import Block, chain_time, hex_value
from app.core.db import lock
from app.core.errors import config_error, not_found, rpc_error
from app.models.entities import (
    EventRecord,
    Merchant,
    PlanDraft,
    SubscriptionSnapshot,
    User,
)
from app.schemas.api import (
    EligibilityResponse,
    EventResponse,
    Page,
    PlanResponse,
    SubscriptionResponse,
    SubscriptionStatus,
    SyncInfo,
    YieldSummary,
)
from app.schemas.types import Address, UintString, utcnow
from app.services.pagination import TIMESTAMP_KEY, Cursor, Limit, paginate
from app.services.sync import plan_terms, sync_through

router = APIRouter(tags=["published plans and subscriptions"])


def live_info(block: Block) -> SyncInfo:
    return SyncInfo(
        block_number=block.number,
        block_hash=block.hash,
        block_timestamp=block.timestamp,
        synced_at=utcnow(),
        source="LIVE",
    )


def plan_response(db: Db, vault: Chain, plan: dict, block: Block) -> PlanResponse:
    id_ = plan["planId"]
    wallet = plan["merchant"].lower()
    draft = db.scalar(
        select(PlanDraft).filter_by(
            **vault.scope,
            onchain_plan_id=id_,
            state="PUBLISHED",
        )
    )
    if draft and draft.client_reference != hex_value(plan["clientReference"]):
        draft = None
    merchant = db.scalar(
        select(Merchant).join(User).where(User.wallet_address == wallet)
    )
    _, price, periods, duration, grace = plan_terms(plan)
    return PlanResponse(
        **vault.scope,
        plan_id=id_,
        merchant_address=wallet,
        merchant=merchant_response(merchant, wallet) if merchant else None,
        title=draft.title if draft else f"Plan #{id_}",
        description=draft.description if draft else "",
        token=vault.deployment.token,
        price_per_period=price,
        total_periods=periods,
        period_duration_seconds=duration,
        grace_period_seconds=grace,
        total_price=price * periods,
        sync=live_info(block),
    )


@router.get("/plans", response_model=Page[PlanResponse])
def list_plans(
    db: Db,
    vault: Chain,
    merchant_address: Address | None = None,
    limit: Limit = 20,
    cursor: Cursor = None,
):
    block = vault.confirmed_block()
    if block is None:
        return {"items": [], "next_cursor": None}
    query = select(EventRecord).filter_by(**vault.scope, event_name="PLAN_CREATED")
    if merchant_address:
        query = query.where(EventRecord.merchant_address == merchant_address)
    events, next_cursor = paginate(
        db,
        query.where(EventRecord.block_number <= block.number),
        (EventRecord.block_number, EventRecord.log_index),
        (int, int),
        limit,
        cursor,
    )
    items = [
        plan_response(db, vault, vault.plan(event.plan_id, block), block)
        for event in events
    ]
    vault.require_canonical(block)
    return {"items": items, "next_cursor": next_cursor}


@router.get("/plans/{plan_id}", response_model=PlanResponse)
def get_plan(plan_id: UintString, db: Db, vault: Chain):
    block = vault.confirmed_block()
    if block is None:
        raise not_found()
    result = plan_response(db, vault, vault.plan(int(plan_id), block), block)
    vault.require_canonical(block)
    return result


def yield_summary(
    vault: Chain, snapshot: SubscriptionSnapshot | None, estimate: int | None = None
):
    mode = vault.deployment.yield_mode
    return YieldSummary(
        mode=mode,
        estimated_unclaimed=0 if mode == "DISABLED" else estimate,
        paid_merchant=snapshot.yield_paid_merchant if snapshot else 0,
        paid_subscriber=snapshot.yield_paid_subscriber if snapshot else 0,
        paid_platform=snapshot.yield_paid_platform if snapshot else 0,
    )


def projection_response(
    vault: Chain, snapshot: SubscriptionSnapshot
) -> SubscriptionResponse:
    info = SyncInfo(
        block_number=snapshot.synced_block_number,
        block_hash=snapshot.synced_block_hash,
        block_timestamp=snapshot.synced_block_timestamp,
        synced_at=snapshot.updated_at,
        source="PROJECTION",
    )
    return SubscriptionResponse.model_validate(
        {
            **{
                name: getattr(snapshot, name)
                for name in SubscriptionResponse.model_fields
                if name
                not in {
                    "token",
                    "next_period_index",
                    "yield_summary",
                    "sync",
                }
            },
            "token": vault.deployment.token,
            "next_period_index": snapshot.completed_periods + 1
            if snapshot.status == "ACTIVE"
            else None,
            "yield_summary": yield_summary(vault, snapshot),
            "sync": info,
        }
    )


def subscription_page(
    db: Db, vault: Chain, query, status, limit: int, cursor: str | None
):
    if status is not None:
        query = query.filter_by(status=status)
    rows, next_cursor = paginate(
        db,
        query,
        (SubscriptionSnapshot.started_at, SubscriptionSnapshot.id),
        TIMESTAMP_KEY,
        limit,
        cursor,
    )
    return {
        "items": [projection_response(vault, row) for row in rows],
        "next_cursor": next_cursor,
    }


@router.get("/me/subscriptions", response_model=Page[SubscriptionResponse])
def my_subscriptions(
    db: Db,
    principal: Current,
    vault: Chain,
    status: SubscriptionStatus | None = None,
    limit: Limit = 20,
    cursor: Cursor = None,
):
    query = select(SubscriptionSnapshot).filter_by(
        **vault.scope,
        subscriber_address=principal.user.wallet_address,
    )
    return subscription_page(db, vault, query, status, limit, cursor)


@router.get("/merchant/subscriptions", response_model=Page[SubscriptionResponse])
def merchant_subscriptions(
    db: Db,
    principal: Current,
    merchant: CurrentMerchant,
    vault: Chain,
    status: SubscriptionStatus | None = None,
    plan_id: UintString | None = None,
    limit: Limit = 20,
    cursor: Cursor = None,
):
    wallet = principal.user.wallet_address
    query = select(SubscriptionSnapshot).filter_by(
        **vault.scope, merchant_address=wallet
    )
    if plan_id is not None:
        event_id = db.scalar(
            select(EventRecord.id).filter_by(
                **vault.scope,
                event_name="PLAN_CREATED",
                plan_id=int(plan_id),
                merchant_address=wallet,
            )
        )
        if event_id is None:
            raise not_found()
        query = query.filter_by(plan_id=int(plan_id))
    return subscription_page(db, vault, query, status, limit, cursor)


def participant(
    vault: Chain, subscription_id: int, wallet: str, block: Block
) -> tuple[dict, dict]:
    sub = vault.subscription(subscription_id, block)
    plan = vault.plan(sub["planId"], block)
    if wallet not in {sub["subscriber"].lower(), plan["merchant"].lower()}:
        raise not_found()
    return sub, plan


def release_times(sub: dict, plan: dict) -> tuple[datetime | None, datetime | None]:
    if sub["status"] != "ACTIVE":
        return None, None
    next_release = sub["nextReleaseAt"]
    return chain_time(next_release), chain_time(next_release + plan["gracePeriod"])


@router.get("/subscriptions/{subscription_id}", response_model=SubscriptionResponse)
def get_subscription(
    subscription_id: UintString,
    db: Db,
    principal: Current,
    vault: Chain,
    settings: Config,
):
    sub_id = int(subscription_id)
    block = vault.confirmed_block()
    if block is None:
        raise not_found()
    sub, plan = participant(vault, sub_id, principal.user.wallet_address, block)
    snapshot = db.scalar(
        select(SubscriptionSnapshot).filter_by(**vault.scope, subscription_id=sub_id)
    )
    if sub["nonce"] and (
        not snapshot
        or snapshot.nonce != sub["nonce"]
        or vault.block(snapshot.synced_block_number).hash != snapshot.synced_block_hash
    ):
        lock(db, vault.lock_key)
        scan_head = vault.checked_head()
        target = min(block.number, vault.confirmed_height(scan_head))
        sync_through(db, vault, settings, scan_head, target, max_batches=2)
        db.commit()
        snapshot = db.scalar(
            select(SubscriptionSnapshot)
            .filter_by(
                **vault.scope,
                subscription_id=sub_id,
            )
            .execution_options(populate_existing=True)
        )
        if snapshot is None or snapshot.nonce != sub["nonce"]:
            raise rpc_error()
    status = sub["status"]
    next_release, refund_at = release_times(sub, plan)
    released = sub["completedPeriods"] * plan["pricePerPeriod"]
    refunded = sub["initialPrincipal"] - sub["remainingPrincipal"] - released
    if refunded < 0 or (status != "REFUNDED" and refunded != 0):
        raise config_error()
    estimate = None
    if vault.deployment.yield_mode == "MOCK":
        estimate = vault.estimate(sub_id, block) if status == "ACTIVE" else 0
    vault.require_canonical(block)
    return SubscriptionResponse(
        **vault.scope,
        subscription_id=sub_id,
        plan_id=sub["planId"],
        merchant_address=plan["merchant"].lower(),
        subscriber_address=sub["subscriber"].lower(),
        token=vault.deployment.token,
        initial_principal=sub["initialPrincipal"],
        remaining_principal=sub["remainingPrincipal"],
        principal_released=released,
        principal_refunded=refunded,
        total_periods=plan["totalPeriods"],
        completed_periods=sub["completedPeriods"],
        next_period_index=sub["completedPeriods"] + 1 if status == "ACTIVE" else None,
        started_at=chain_time(sub["startedAt"]),
        next_release_at=next_release,
        refund_available_at=refund_at,
        nonce=sub["nonce"],
        status=status,
        yield_summary=yield_summary(
            vault, snapshot if sub["nonce"] else None, estimate
        ),
        sync=live_info(block),
    )


@router.get(
    "/subscriptions/{subscription_id}/eligibility", response_model=EligibilityResponse
)
def eligibility(subscription_id: UintString, principal: Current, vault: Chain):
    block = vault.checked_head()
    sub, plan = participant(
        vault, int(subscription_id), principal.user.wallet_address, block
    )
    next_release, refund_at = release_times(sub, plan)
    if next_release is None:
        reason = "TERMINAL_STATE"
    elif block.timestamp < next_release:
        reason = "TOO_EARLY"
    elif block.timestamp >= refund_at:
        reason = "REFUND_WINDOW_OPEN"
    else:
        reason = "READY"
    vault.require_canonical(block)
    return EligibilityResponse(
        subscription_id=subscription_id,
        status=sub["status"],
        can_check_in=reason == "READY",
        can_refund=reason == "REFUND_WINDOW_OPEN",
        next_period_index=sub["completedPeriods"] + 1 if next_release else None,
        nonce=sub["nonce"],
        next_release_at=next_release,
        refund_available_at=refund_at,
        reasons=[reason],
        sync=live_info(block),
    )


@router.get(
    "/subscriptions/{subscription_id}/events", response_model=Page[EventResponse]
)
def subscription_events(
    subscription_id: UintString,
    db: Db,
    principal: Current,
    vault: Chain,
    limit: Limit = 20,
    cursor: Cursor = None,
):
    snapshot = db.scalar(
        select(SubscriptionSnapshot).filter_by(
            **vault.scope,
            subscription_id=int(subscription_id),
        )
    )
    if snapshot is None or principal.user.wallet_address not in {
        snapshot.merchant_address,
        snapshot.subscriber_address,
    }:
        raise not_found()
    query = select(EventRecord).filter_by(
        **vault.scope, subscription_id=int(subscription_id)
    )
    rows, next_cursor = paginate(
        db,
        query,
        (EventRecord.block_number, EventRecord.log_index),
        (int, int),
        limit,
        cursor,
    )
    items = [
        EventResponse.model_validate(
            {
                **{
                    field: getattr(row, field)
                    for field in EventResponse.model_fields
                    if field != "explorer_url"
                },
                "explorer_url": vault.explorer(row.tx_hash),
            }
        )
        for row in rows
    ]
    return {"items": items, "next_cursor": next_cursor}
