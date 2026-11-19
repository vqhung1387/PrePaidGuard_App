from base64 import urlsafe_b64encode
from datetime import timedelta
from uuid import UUID

import pytest
from eth_account import Account
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import EventRecord, Merchant, PlanDraft, SubscriptionSnapshot
from app.schemas.types import utcnow
from tests.fake_rpc import TOKEN
from tests.test_api import API, assert_error, login


def pages(client, path, headers, **filters):
    items, cursor = [], None
    while True:
        response = client.get(
            API + path,
            headers=headers,
            params={"limit": 100, **filters, **({"cursor": cursor} if cursor else {})},
        )
        assert response.status_code == 200, response.json()
        page = response.json()
        items.extend(page["items"])
        next_cursor = page["next_cursor"]
        if next_cursor is None:
            return items
        assert next_cursor != cursor
        cursor = next_cursor


def test_drafts_over_100_with_tied_timestamps_and_other_owner(harness):
    client, app, vault, _ = harness
    owner, other = login(client, Account.create()), login(client, Account.create())
    for headers in (owner, other):
        assert (
            client.post(
                API + "/merchants", headers=headers, json={"business_name": "Gym"}
            ).status_code
            == 201
        )
    with Session(app.state.engine) as db, db.begin():
        merchants = list(db.scalars(select(Merchant).order_by(Merchant.created_at)))
        now = utcnow()
        for i in range(1, 207):
            db.add(
                PlanDraft(
                    **vault.scope,
                    id=UUID(int=i),
                    merchant_id=merchants[0 if i <= 205 else 1].id,
                    client_reference=f"0x{i:064x}",
                    title=f"Plan {i}",
                    description="",
                    token_address=TOKEN,
                    price_per_period=1,
                    total_periods=1,
                    period_duration_seconds=1,
                    grace_period_seconds=1,
                    created_at=now,
                )
            )
    result = pages(client, "/plan-drafts", owner)
    assert [item["id"] for item in result] == [
        str(UUID(int=i)) for i in range(205, 0, -1)
    ]
    assert len(pages(client, "/plan-drafts", other)) == 1


def test_subscription_and_event_pages_preserve_scope_filter_and_ties(harness):
    client, app, vault, _ = harness
    merchant, subscriber, other = Account.create(), Account.create(), Account.create()
    mh, sh, oh = [login(client, wallet) for wallet in (merchant, subscriber, other)]
    assert (
        client.post(
            API + "/merchants", headers=mh, json={"business_name": "Gym"}
        ).status_code
        == 201
    )
    now = utcnow()
    with Session(app.state.engine) as db, db.begin():
        for i in range(1, 208):
            state = "COMPLETED" if i == 206 else "REFUNDED" if i == 207 else "ACTIVE"
            db.add(
                SubscriptionSnapshot(
                    **vault.scope,
                    id=UUID(int=i),
                    subscription_id=i,
                    plan_id=1,
                    merchant_address=merchant.address.lower(),
                    subscriber_address=(
                        subscriber if i <= 206 else other
                    ).address.lower(),
                    price_per_period=1,
                    initial_principal=1,
                    remaining_principal=1 if state == "ACTIVE" else 0,
                    total_periods=1,
                    completed_periods=1 if state == "COMPLETED" else 0,
                    started_at=now,
                    next_release_at=now + timedelta(seconds=1),
                    refund_available_at=now + timedelta(seconds=2),
                    nonce=0,
                    status=state,
                    principal_released=1 if state == "COMPLETED" else 0,
                    principal_refunded=1 if state == "REFUNDED" else 0,
                    yield_paid_merchant=0,
                    yield_paid_subscriber=0,
                    yield_paid_platform=0,
                    synced_block_number=100,
                    synced_block_hash="0x" + "01" * 32,
                    synced_block_timestamp=now,
                )
            )
        for i in range(121):
            db.add(
                EventRecord(
                    **vault.scope,
                    tx_hash="0x" + "02" * 32,
                    log_index=i,
                    block_number=100,
                    block_hash="0x" + "01" * 32,
                    block_timestamp=now,
                    event_name="PERIOD_RELEASED",
                    plan_id=1,
                    subscription_id=1,
                    merchant_address=merchant.address.lower(),
                    subscriber_address=subscriber.address.lower(),
                    payload={},
                )
            )
    for path, headers in [("/me/subscriptions", sh), ("/merchant/subscriptions", mh)]:
        active = pages(client, path, headers, status="ACTIVE")
        assert [item["subscription_id"] for item in active] == [
            str(i) for i in range(205, 0, -1)
        ]
        completed = pages(client, path, headers, status="COMPLETED")
        assert [item["subscription_id"] for item in completed] == ["206"]
    assert len(pages(client, "/me/subscriptions", sh)) == 206
    assert len(pages(client, "/me/subscriptions", oh)) == 1
    assert pages(client, "/me/subscriptions", sh, status="REFUNDED") == []
    events = pages(client, "/subscriptions/1/events", sh)
    assert [event["log_index"] for event in events] == list(range(120, -1, -1))
    assert len({event["id"] for event in events}) == 121
    assert_error(
        client.get(API + "/subscriptions/1/events", headers=oh), 404, "NOT_FOUND"
    )


@pytest.mark.parametrize(
    "raw", ["-1|0", f"{2**256}|0", "1|not-an-int", "1|2|3", "\xff"]
)
def test_bad_event_cursors_return_validation_error(harness, raw):
    client, _, _, _ = harness
    cursor = urlsafe_b64encode(raw.encode()).decode()
    assert_error(
        client.get(API + "/plans", params={"cursor": cursor}), 422, "VALIDATION_ERROR"
    )
