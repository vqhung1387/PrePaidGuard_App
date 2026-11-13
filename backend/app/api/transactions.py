from eth_abi.exceptions import DecodingError
from fastapi import APIRouter
from sqlalchemy import select
from web3.exceptions import Web3Exception

from app.api.dependencies import Config, Current, Db
from app.api.metadata import own_draft
from app.api.system import Chain
from app.blockchain.vault import ACTION, hex_value
from app.core.db import lock
from app.core.errors import ApiError, not_found, rpc_error
from app.models.entities import EventRecord, TransactionRecord, User
from app.schemas.api import TransactionResponse, TransactionSubmit
from app.schemas.types import Hash32, utcnow
from app.services.sync import (
    draft_terms,
    plan_terms,
    reconcile_plan_draft,
    sync_through,
)

router = APIRouter(tags=["transaction tracking"])


def mismatch() -> ApiError:
    return ApiError(
        409, "TX_MISMATCH", "Giao dịch không khớp hành động hoặc tài nguyên."
    )


def conflict() -> ApiError:
    return ApiError(
        409, "TRANSACTION_CONFLICT", "Giao dịch đang được theo dõi với thông tin khác."
    )


def _clear(record: TransactionRecord) -> None:
    record.status = "SUBMITTED"
    record.block_hash = None
    record.block_number = None
    record.failure_code = None


def _verify_input(
    vault: Chain, record: TransactionRecord, draft, tx, wallet: str
) -> None:
    if (
        hex_value(tx["hash"]) != record.tx_hash
        or (tx.get("to") or "").lower() != vault.deployment.vault_address
        or tx["from"].lower() != wallet
        or (
            tx.get("chainId") is not None and tx["chainId"] != vault.deployment.chain_id
        )
    ):
        raise mismatch()
    try:
        name, args = vault.calldata(tx["input"])
        if name != ACTION[record.expected_action][0]:
            raise mismatch()
        if name == "createPlan":
            valid = hex_value(args["clientReference"]) == draft.client_reference
            valid = valid and plan_terms(args) == draft_terms(draft)
        elif name == "subscribe":
            valid = args["planId"] == record.plan_id
        elif name == "checkInWithSignature":
            message = next(iter(args.values()))
            valid = (
                message["subscriptionId"] == record.subscription_id
                and message["merchant"].lower() == wallet
            )
        else:
            valid = args["subscriptionId"] == record.subscription_id
    except (DecodingError, Web3Exception, ValueError, KeyError, TypeError):
        raise mismatch() from None
    if not valid:
        raise mismatch()


def _verify_success(
    vault: Chain, record: TransactionRecord, draft, tx, receipt, wallet: str, block
):
    events = [
        entry for raw in receipt["logs"] if (entry := vault.decode_log(raw)) is not None
    ]
    if len(events) != 1 or events[0].name != ACTION[record.expected_action][1]:
        raise mismatch()
    entry = events[0]
    args = entry.args
    if (
        entry.tx_hash != record.tx_hash
        or entry.block_number != block.number
        or entry.block_hash != block.hash
    ):
        raise mismatch()
    if entry.name == "PLAN_CREATED":
        if (
            args["merchant"].lower() != wallet
            or hex_value(args["clientReference"]) != draft.client_reference
            or plan_terms(args) != draft_terms(draft)
        ):
            raise mismatch()
    elif entry.name == "SUBSCRIBED":
        if args["subscriber"].lower() != wallet or args["planId"] != record.plan_id:
            raise mismatch()
    else:
        if args["subscriptionId"] != record.subscription_id:
            raise mismatch()
        sub = vault.subscription(record.subscription_id, block)
        if sub["planId"] != args["planId"]:
            raise mismatch()
        if entry.name == "REFUNDED" and sub["subscriber"].lower() != wallet:
            raise mismatch()
        if entry.name == "PERIOD_RELEASED":
            plan = vault.plan(sub["planId"], block)
            message = next(iter(vault.calldata(tx["input"])[1].values()))
            if (
                plan["merchant"].lower() != wallet
                or args["periodIndex"] != message["periodIndex"]
                or args["nonceAfter"] != message["nonce"] + 1
            ):
                raise mismatch()
    return entry


def _track(
    db: Db,
    vault: Chain,
    settings: Config,
    record: TransactionRecord,
    user: User,
    lookup=None,
):
    head = vault.checked_head()
    confirmed = vault.confirmed_height(head)
    if record.status != "SUBMITTED":
        if (
            record.block_number <= confirmed
            and vault.block(record.block_number).hash == record.block_hash
        ):
            return
        _clear(record)
    draft = None
    if record.plan_draft_id is not None:
        draft = own_draft(db, record.plan_draft_id, user.id, vault, for_update=True)
    tx, receipt = lookup if lookup is not None else vault.tx_receipt(record.tx_hash)
    record.checked_at = utcnow()
    if tx is None:
        return
    _verify_input(vault, record, draft, tx, user.wallet_address)
    if record.subscription_id is not None:
        try:
            sub = vault.subscription(record.subscription_id, head)
            sender = sub["subscriber"]
            if record.expected_action == "CHECK_IN":
                sender = vault.plan(sub["planId"], head)["merchant"]
        except ApiError as error:
            if error.status == 404:
                raise mismatch() from None
            raise
        if sender.lower() != user.wallet_address:
            raise mismatch()
    if receipt is None:
        return
    if (
        hex_value(receipt["transactionHash"]) != record.tx_hash
        or (receipt.get("to") or "").lower() != vault.deployment.vault_address
        or receipt["from"].lower() != user.wallet_address
    ):
        raise mismatch()
    number = receipt["blockNumber"]
    if tx["blockNumber"] != number:
        raise rpc_error()
    if number < vault.deployment.deployment_block:
        raise mismatch()
    if number > confirmed:
        return
    block = vault.block(number)
    if (
        hex_value(receipt["blockHash"]) != block.hash
        or hex_value(tx["blockHash"]) != block.hash
    ):
        raise rpc_error()
    if receipt["status"] == 0:
        record.status = "REVERTED"
        record.failure_code = "TRANSACTION_REVERTED"
    elif receipt["status"] == 1:
        entry = _verify_success(
            vault, record, draft, tx, receipt, user.wallet_address, block
        )
        if not sync_through(db, vault, settings, head, number, max_batches=2):
            return
        indexed = db.scalar(
            select(EventRecord).filter_by(
                **vault.scope,
                tx_hash=record.tx_hash,
                log_index=entry.index,
                block_hash=block.hash,
                event_name=entry.name,
                plan_id=entry.args["planId"],
                subscription_id=entry.args.get("subscriptionId"),
            )
        )
        if indexed is None or indexed.payload != entry.payload:
            raise rpc_error()
        if draft and draft.state == "DRAFT":
            reconcile_plan_draft(db, vault, entry)
        if draft and (
            draft.onchain_plan_id != indexed.plan_id
            or draft.publication_tx_hash != record.tx_hash
        ):
            raise mismatch()
        record.status = "CONFIRMED"
    else:
        raise rpc_error()
    vault.require_canonical(block)
    record.block_number = number
    record.block_hash = block.hash


def _response(db: Db, vault: Chain, record: TransactionRecord):
    event_ids = []
    if record.status == "CONFIRMED":
        event_ids = list(
            db.scalars(
                select(EventRecord.id)
                .filter_by(
                    **vault.scope,
                    tx_hash=record.tx_hash,
                    block_hash=record.block_hash,
                    event_name=ACTION[record.expected_action][1],
                )
                .order_by(EventRecord.log_index)
            )
        )
    return TransactionResponse.model_validate(
        {
            **{
                field: getattr(record, field)
                for field in TransactionResponse.model_fields
                if field
                not in {
                    "event_ids",
                    "explorer_url",
                }
            },
            "event_ids": event_ids,
            "explorer_url": vault.explorer(record.tx_hash),
        }
    )


@router.post("/transactions", status_code=202, response_model=TransactionResponse)
def submit(
    body: TransactionSubmit, db: Db, principal: Current, vault: Chain, settings: Config
):
    lock(db, vault.lock_key)
    user = principal.user
    refs = {
        "plan_draft_id": getattr(body, "plan_draft_id", None),
        "plan_id": int(body.plan_id) if hasattr(body, "plan_id") else None,
        "subscription_id": int(body.subscription_id)
        if hasattr(body, "subscription_id")
        else None,
    }
    record = db.scalar(
        select(TransactionRecord).filter_by(
            chain_id=vault.deployment.chain_id,
            tx_hash=body.tx_hash,
        )
    )
    lookup = None
    if record and record.submitted_by_user_id != user.id:
        if record.status != "SUBMITTED":
            raise conflict()
        vault.checked_head()
        lookup = vault.tx_receipt(body.tx_hash)
        if lookup[0] is None or lookup[0]["from"].lower() != user.wallet_address:
            raise conflict()
        # The first reporter cannot reserve someone else's hash before the node sees it.
        db.delete(record)
        db.flush()
        record = None
    if record is None:
        record = TransactionRecord(
            **vault.scope,
            submitted_by_user_id=user.id,
            tx_hash=body.tx_hash,
            expected_action=body.action,
            **refs,
            status="SUBMITTED",
        )
        db.add(record)
    elif (
        record.vault_address != vault.deployment.vault_address
        or record.expected_action != body.action
        or any(getattr(record, key) != value for key, value in refs.items())
    ):
        raise conflict()
    _track(db, vault, settings, record, user, lookup)
    db.commit()
    return _response(db, vault, record)


@router.get("/transactions/{tx_hash}", response_model=TransactionResponse)
def transaction_status(
    tx_hash: Hash32, db: Db, principal: Current, vault: Chain, settings: Config
):
    lock(db, vault.lock_key)
    record = db.scalar(
        select(TransactionRecord).filter_by(
            **vault.scope,
            tx_hash=tx_hash,
            submitted_by_user_id=principal.user.id,
        )
    )
    if record is None:
        raise not_found()
    _track(db, vault, settings, record, principal.user)
    db.commit()
    return _response(db, vault, record)
