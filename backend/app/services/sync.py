import argparse
from collections.abc import Iterable

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.blockchain.vault import Block, Log, Vault, chain_time, hex_value
from app.core.config import Settings
from app.core.db import lock, make_engine
from app.core.errors import ApiError, config_error, rpc_error
from app.models.entities import (
    EventRecord,
    Merchant,
    PlanDraft,
    ProjectionIssue,
    SubscriptionSnapshot,
    SyncCursor,
    TransactionRecord,
    User,
)
from app.schemas.types import UINT_MAX, timestamp_supported, utcnow


def plan_terms(values: dict) -> tuple:
    return (
        values["token"].lower(),
        values["pricePerPeriod"],
        values["totalPeriods"],
        values["periodDuration"],
        values["gracePeriod"],
    )


def draft_terms(draft: PlanDraft) -> tuple:
    return (
        draft.token_address,
        draft.price_per_period,
        draft.total_periods,
        draft.period_duration_seconds,
        draft.grace_period_seconds,
    )


def reconcile_plan_draft(db: Session, vault: Vault, entry: Log) -> None:
    args = entry.args
    draft = db.scalar(
        select(PlanDraft)
        .filter_by(client_reference=hex_value(args["clientReference"]), **vault.scope)
        .join(Merchant)
        .join(User)
        .where(User.wallet_address == args["merchant"].lower())
        .with_for_update(of=PlanDraft)
    )
    if draft and draft.state == "DRAFT" and draft_terms(draft) == plan_terms(args):
        draft.state = "PUBLISHED"
        draft.onchain_plan_id = args["planId"]
        draft.publication_tx_hash = entry.tx_hash


def _plan_event(db: Session, vault: Vault, plan_id: int) -> EventRecord:
    plan = db.scalars(
        select(EventRecord).filter_by(
            **vault.scope,
            plan_id=plan_id,
            event_name="PLAN_CREATED",
        )
    ).one_or_none()
    if plan is None:
        raise rpc_error()
    return plan


def _record_events(db: Session, vault: Vault, logs: Iterable[Log]) -> set[int]:
    affected = set()
    blocks = {}
    for entry in logs:
        if entry.block_number not in blocks:
            blocks[entry.block_number] = vault.block(entry.block_number)
        block = blocks[entry.block_number]
        if block.hash != entry.block_hash:
            raise rpc_error()
        args = entry.args
        plan_id = args["planId"]
        sub_id = args.get("subscriptionId")
        existing = db.scalars(
            select(EventRecord).filter_by(
                **vault.scope,
                tx_hash=entry.tx_hash,
                log_index=entry.index,
            )
        ).one_or_none()
        if existing:
            if existing.block_hash != entry.block_hash:
                raise rpc_error()
            continue
        subscriber = None
        if entry.name == "PLAN_CREATED":
            token, price, periods, duration, grace = plan_terms(args)
            if (
                token != vault.deployment.token.address
                or not 1 <= periods <= 120
                or not 0 < price * periods <= UINT_MAX
                or duration <= 0
                or grace <= 0
                or duration + grace >= 2**63
            ):
                raise config_error()
            merchant = args["merchant"].lower()
            reconcile_plan_draft(db, vault, entry)
        else:
            merchant = _plan_event(db, vault, plan_id).merchant_address
            if entry.name == "SUBSCRIBED":
                subscriber = args["subscriber"].lower()
            else:
                opened = db.scalars(
                    select(EventRecord).filter_by(
                        **vault.scope,
                        subscription_id=sub_id,
                        event_name="SUBSCRIBED",
                    )
                ).one_or_none()
                if opened is None or opened.plan_id != plan_id:
                    raise rpc_error()
                subscriber = opened.subscriber_address
            affected.add(sub_id)
        db.add(
            EventRecord(
                **vault.scope,
                tx_hash=entry.tx_hash,
                log_index=entry.index,
                block_number=block.number,
                block_hash=block.hash,
                block_timestamp=block.timestamp,
                event_name=entry.name,
                plan_id=plan_id,
                subscription_id=sub_id,
                merchant_address=merchant,
                subscriber_address=subscriber,
                payload=entry.payload,
            )
        )
    db.flush()
    return affected


def _project_subscription(db: Session, vault: Vault, sub_id: int, block: Block) -> None:
    events = list(
        db.scalars(
            select(EventRecord)
            .filter_by(
                **vault.scope,
                subscription_id=sub_id,
            )
            .order_by(EventRecord.block_number, EventRecord.log_index)
        )
    )
    opened = events[0]
    if opened.event_name != "SUBSCRIBED":
        raise rpc_error()
    plan = _plan_event(db, vault, opened.plan_id).payload
    price = int(plan["pricePerPeriod"])
    periods = int(plan["totalPeriods"])
    principal = int(opened.payload["principal"])
    if principal != price * periods:
        raise config_error()
    released = refunded = completed = nonce = 0
    paid = {"merchantYield": 0, "subscriberYield": 0, "platformYield": 0}
    next_release = int(opened.payload["nextReleaseAt"])
    status = "ACTIVE"
    for event in events[1:]:
        payload = event.payload
        if status != "ACTIVE" or event.plan_id != opened.plan_id:
            raise rpc_error()
        nonce += 1
        if int(payload["nonceAfter"]) != nonce:
            raise rpc_error()
        amount = int(payload["principal"])
        if event.event_name == "PERIOD_RELEASED":
            completed += 1
            released += amount
            if (
                amount != price
                or int(payload["periodIndex"]) != completed
                or completed > periods
                or payload["completed"] != (completed == periods)
            ):
                raise config_error()
            next_release = int(payload["nextReleaseAt"])
            if completed == periods:
                status = "COMPLETED"
        elif event.event_name == "REFUNDED" and amount == principal - released:
            status = "REFUNDED"
            refunded = amount
        else:
            raise config_error()
        for name in paid:
            paid[name] += int(payload[name])
    remaining = principal - released - refunded
    raw_times = {"started_at": int(opened.payload["startedAt"])}
    if status == "ACTIVE":
        raw_times.update(
            next_release_at=next_release,
            refund_available_at=next_release + int(plan["gracePeriod"]),
        )
    issue = db.scalar(
        select(ProjectionIssue).filter_by(**vault.scope, subscription_id=sub_id)
    )
    if not all(timestamp_supported(value) for value in raw_times.values()):
        # Preserve event evidence and explicitly quarantine just this read model.
        # Never retain a stale balance from an earlier valid snapshot.
        db.execute(
            delete(SubscriptionSnapshot).filter_by(
                **vault.scope, subscription_id=sub_id
            )
        )
        if issue is None:
            issue = ProjectionIssue(**vault.scope, subscription_id=sub_id)
            db.add(issue)
        issue.plan_id = opened.plan_id
        issue.merchant_address = opened.merchant_address
        issue.subscriber_address = opened.subscriber_address
        issue.code = "UNSUPPORTED_TIMESTAMP"
        issue.raw_timestamps = {key: str(value) for key, value in raw_times.items()}
        issue.synced_block_number = block.number
        issue.synced_block_hash = block.hash
        issue.updated_at = utcnow()
        return
    if issue is not None:
        db.delete(issue)
    snapshot = db.scalars(
        select(SubscriptionSnapshot).filter_by(
            **vault.scope,
            subscription_id=sub_id,
        )
    ).one_or_none()
    if snapshot is None:
        snapshot = SubscriptionSnapshot(**vault.scope, subscription_id=sub_id)
        db.add(snapshot)
    snapshot.plan_id = opened.plan_id
    snapshot.merchant_address = opened.merchant_address
    snapshot.subscriber_address = opened.subscriber_address
    snapshot.price_per_period = price
    snapshot.initial_principal = principal
    snapshot.remaining_principal = remaining
    snapshot.principal_released = released
    snapshot.principal_refunded = refunded
    snapshot.total_periods = periods
    snapshot.completed_periods = completed
    snapshot.started_at = chain_time(int(opened.payload["startedAt"]))
    snapshot.next_release_at = chain_time(next_release) if status == "ACTIVE" else None
    snapshot.refund_available_at = (
        chain_time(next_release + int(plan["gracePeriod"]))
        if status == "ACTIVE"
        else None
    )
    snapshot.status = status
    snapshot.nonce = nonce
    snapshot.yield_paid_merchant = paid["merchantYield"]
    snapshot.yield_paid_subscriber = paid["subscriberYield"]
    snapshot.yield_paid_platform = paid["platformYield"]
    snapshot.synced_block_number = block.number
    snapshot.synced_block_hash = block.hash
    snapshot.synced_block_timestamp = block.timestamp
    snapshot.updated_at = utcnow()


def reset_projection(db: Session, vault: Vault) -> None:
    for model in (EventRecord, SubscriptionSnapshot, ProjectionIssue, SyncCursor):
        db.execute(delete(model).filter_by(**vault.scope))
    db.execute(
        update(PlanDraft)
        .filter_by(**vault.scope, state="PUBLISHED")
        .values(
            state="DRAFT",
            onchain_plan_id=None,
            publication_tx_hash=None,
        )
    )
    db.execute(
        update(TransactionRecord)
        .filter_by(**vault.scope)
        .values(
            status="SUBMITTED",
            block_number=None,
            block_hash=None,
            failure_code=None,
            checked_at=None,
        )
    )


def sync_through(
    db: Session,
    vault: Vault,
    settings: Settings,
    head: Block,
    target: int,
    *,
    max_batches: int,
) -> bool:
    """Scan confirmed ranges under the deployment lock held by the caller."""
    cursor = db.get(
        SyncCursor, (vault.deployment.chain_id, vault.deployment.vault_address)
    )
    start = vault.deployment.deployment_block
    if cursor and (
        cursor.last_processed_block > head.number
        or vault.block(cursor.last_processed_block).hash
        != cursor.last_processed_block_hash
    ):
        reset_projection(db, vault)
        cursor = None
    for _ in range(max_batches):
        previous = cursor.last_processed_block if cursor else start - 1
        if previous >= target:
            return True
        last = min(target, previous + settings.sync_batch_size)
        first = max(start, previous + 1 - settings.sync_overlap)
        block = vault.block(last)
        for sub_id in _record_events(db, vault, vault.logs(first, last)):
            _project_subscription(db, vault, sub_id, block)
        if cursor and vault.block(previous).hash != cursor.last_processed_block_hash:
            raise rpc_error()
        vault.require_canonical(block)
        if cursor is None:
            cursor = SyncCursor(**vault.scope)
            db.add(cursor)
        cursor.last_processed_block = last
        cursor.last_processed_block_hash = block.hash
        db.flush()
    return cursor is not None and cursor.last_processed_block >= target


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync confirmed Vault logs to PostgreSQL"
    )
    parser.add_argument(
        "--rebuild", action="store_true", help="Rebuild projections from deployment"
    )
    parser.add_argument("--max-batches", type=int, default=100)
    args = parser.parse_args()
    if args.max_batches < 1:
        parser.error("--max-batches must be positive")
    settings = Settings()
    try:
        vault = Vault(settings)
        engine = make_engine(settings)
        try:
            target, complete = run_scan(
                engine,
                vault,
                settings,
                max_batches=args.max_batches,
                rebuild=args.rebuild,
            )
        finally:
            engine.dispose()
        if complete:
            print(f"Synced through block {target}.")
        else:
            print(f"Batch limit reached. Run again to continue toward block {target}.")
    except ApiError as exc:
        parser.exit(1, f"{exc.code}: {exc.message}\n")


def run_scan(
    engine, vault: Vault, settings: Settings, *, max_batches: int, rebuild: bool = False
):
    target = None
    for batch in range(max_batches):
        with Session(engine) as db, db.begin():
            lock(db, vault.lock_key)
            head = vault.checked_head()
            confirmed = vault.confirmed_height(head)
            if target is None:
                vault.check_contract(head)
                target = confirmed
            target = min(target, confirmed)
            if rebuild and batch == 0:
                reset_projection(db, vault)
            complete = sync_through(db, vault, settings, head, target, max_batches=1)
        if complete:
            return target, True
    return target, False


if __name__ == "__main__":
    main()
