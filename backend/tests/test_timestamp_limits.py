from datetime import UTC, datetime

import pytest
from eth_account import Account
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.blockchain.vault import chain_time
from app.core.errors import ApiError
from app.models.entities import (
    EventRecord,
    ProjectionIssue,
    SubscriptionSnapshot,
    SyncCursor,
)
from app.schemas.api import PlanTerms
from app.schemas.types import MAX_TIMESTAMP
from app.services.sync import run_scan
from tests.fake_rpc import BASE_TIME, TOKEN
from tests.test_api import API, assert_error, login


def test_plan_terms_bound_the_entire_schedule(monkeypatch):
    now = datetime(2026, 11, 13, tzinfo=UTC)
    monkeypatch.setattr("app.schemas.api.utcnow", lambda: now)
    remaining = MAX_TIMESTAMP - int(now.timestamp())
    values = {
        "title": "Boundary",
        "price_per_period": "1",
        "total_periods": 1,
        "period_duration_seconds": remaining - 20,
        "grace_period_seconds": 20,
    }
    assert PlanTerms(**values).period_duration_seconds == remaining - 20
    for changes in (
        {"period_duration_seconds": remaining - 19},
        {"grace_period_seconds": 21},
        {"period_duration_seconds": 1_000_000_000_000},
    ):
        with pytest.raises(ValidationError):
            PlanTerms(**{**values, **changes})


def test_legacy_timestamp_is_quarantined_without_stopping_following_events(harness):
    client, app, vault, rpc = harness
    merchant, subscriber, outsider = (
        Account.create(),
        Account.create(),
        Account.create(),
    )
    mh, sh, xh = (
        login(client, merchant),
        login(client, subscriber),
        login(client, outsider),
    )
    assert (
        client.post(
            API + "/merchants", headers=mh, json={"business_name": "Gym"}
        ).status_code
        == 201
    )
    for plan_id, duration, opened_at in ((1, 1_000_000_000_000, 100), (2, 10, 102)):
        plan = {
            "planId": plan_id,
            "merchant": merchant.address,
            "clientReference": bytes([plan_id]) * 32,
            "token": TOKEN,
            "pricePerPeriod": 1,
            "totalPeriods": 1,
            "periodDuration": duration,
            "gracePeriod": 20,
        }
        rpc.plans[plan_id] = plan
        rpc.add_tx(
            plan_id * 10,
            opened_at,
            merchant.address,
            "createPlan",
            [plan["clientReference"], TOKEN, 1, 1, duration, 20],
            event_name="PlanCreated",
            event_args=plan,
        )
        sub = {
            "subscriptionId": plan_id,
            "planId": plan_id,
            "subscriber": subscriber.address,
            "initialPrincipal": 1,
            "remainingPrincipal": 1,
            "completedPeriods": 0,
            "nonce": 0,
            "startedAt": BASE_TIME + opened_at + 1,
            "nextReleaseAt": BASE_TIME + opened_at + 1 + duration,
            "status": 0,
        }
        rpc.subs[plan_id] = sub
        rpc.add_tx(
            plan_id * 10 + 1,
            opened_at + 1,
            subscriber.address,
            "subscribe",
            [plan_id],
            event_name="Subscribed",
            event_args={
                key: sub[key]
                for key in (
                    "subscriptionId",
                    "planId",
                    "subscriber",
                    "startedAt",
                    "nextReleaseAt",
                )
            }
            | {"principal": 1},
        )
    rpc.head = 105
    assert run_scan(app.state.engine, vault, app.state.settings, max_batches=3) == (
        104,
        True,
    )
    # Retrying/rebuilding retains raw events and one explicit issue, never duplicate entries.
    assert run_scan(app.state.engine, vault, app.state.settings, max_batches=3) == (
        104,
        True,
    )
    with Session(app.state.engine) as db:
        assert db.scalar(select(SyncCursor.last_processed_block)) == 104
        assert db.scalar(select(func.count()).select_from(EventRecord)) == 4
        assert db.scalar(select(func.count()).select_from(ProjectionIssue)) == 1
        assert list(db.scalars(select(SubscriptionSnapshot.subscription_id))) == [2]
        issue = db.scalar(select(ProjectionIssue))
        assert issue.raw_timestamps["next_release_at"] == str(
            rpc.subs[1]["nextReleaseAt"]
        )
    page = client.get(API + "/me/subscriptions", headers=sh)
    assert page.status_code == 200, page.json()
    assert [item["subscription_id"] for item in page.json()["items"]] == ["2"]
    assert page.json()["issues"][0]["subscription_id"] == "1"
    assert page.json()["issues"][0]["code"] == "UNSUPPORTED_TIMESTAMP"
    assert client.get(API + "/me/subscriptions", headers=xh).json()["issues"] == []
    assert (
        client.get(API + "/merchant/subscriptions", headers=mh).json()["issues"][0][
            "subscription_id"
        ]
        == "1"
    )
    assert (
        client.get(
            API + "/merchant/subscriptions", headers=mh, params={"plan_id": "2"}
        ).json()["issues"]
        == []
    )
    assert client.get(API + "/subscriptions/2", headers=sh).status_code == 200
    for suffix in ("", "/eligibility"):
        assert_error(
            client.get(API + "/subscriptions/1" + suffix, headers=sh),
            409,
            "UNSUPPORTED_TIMESTAMP",
        )
        assert_error(
            client.get(API + "/subscriptions/1" + suffix, headers=xh), 404, "NOT_FOUND"
        )
    history = client.get(API + "/subscriptions/1/events", headers=sh)
    assert history.status_code == 200 and len(history.json()["items"]) == 1
    assert_error(
        client.get(API + "/subscriptions/1/events", headers=xh), 404, "NOT_FOUND"
    )
    assert run_scan(
        app.state.engine, vault, app.state.settings, max_batches=3, rebuild=True
    ) == (104, True)
    assert (
        client.get(API + "/me/subscriptions", headers=sh).json()["issues"][0][
            "subscription_id"
        ]
        == "1"
    )


@pytest.mark.parametrize(
    ("seconds", "expected"),
    [
        (0, "1970-01-01T00:00:00+00:00"),
        (32536850400, "3001-01-19T22:00:00+00:00"),
        (MAX_TIMESTAMP, "9999-12-31T23:59:59+00:00"),
    ],
)
def test_chain_time_covers_declared_range_on_all_platforms(seconds, expected):
    assert chain_time(seconds).isoformat() == expected


@pytest.mark.parametrize("seconds", [-1, MAX_TIMESTAMP + 1, True, 0.5, "1"])
def test_chain_time_rejects_unsupported_values(seconds):
    with pytest.raises(ApiError) as error:
        chain_time(seconds)
    assert error.value.status == 503
    assert error.value.code == "CONFIG_MISMATCH"


def test_scanner_projects_the_exact_maximum_supported_refund_time(harness):
    client, app, vault, rpc = harness
    merchant, subscriber = Account.create(), Account.create()
    sh = login(client, subscriber)
    started = BASE_TIME + 101
    duration = MAX_TIMESTAMP - started - 20
    plan = {
        "planId": 1,
        "merchant": merchant.address,
        "clientReference": b"m" * 32,
        "token": TOKEN,
        "pricePerPeriod": 1,
        "totalPeriods": 1,
        "periodDuration": duration,
        "gracePeriod": 20,
    }
    rpc.plans[1] = plan
    rpc.add_tx(
        90,
        100,
        merchant.address,
        "createPlan",
        [plan["clientReference"], TOKEN, 1, 1, duration, 20],
        event_name="PlanCreated",
        event_args=plan,
    )
    sub = {
        "subscriptionId": 1,
        "planId": 1,
        "subscriber": subscriber.address,
        "initialPrincipal": 1,
        "remainingPrincipal": 1,
        "completedPeriods": 0,
        "nonce": 0,
        "startedAt": started,
        "nextReleaseAt": MAX_TIMESTAMP - 20,
        "status": 0,
    }
    rpc.subs[1] = sub
    rpc.add_tx(
        91,
        101,
        subscriber.address,
        "subscribe",
        [1],
        event_name="Subscribed",
        event_args={
            key: sub[key]
            for key in (
                "subscriptionId",
                "planId",
                "subscriber",
                "startedAt",
                "nextReleaseAt",
            )
        }
        | {"principal": 1},
    )
    rpc.head = 103
    assert run_scan(app.state.engine, vault, app.state.settings, max_batches=3) == (
        102,
        True,
    )
    with Session(app.state.engine) as db:
        assert db.scalar(select(SyncCursor.last_processed_block)) == 102
        assert db.scalar(select(func.count()).select_from(ProjectionIssue)) == 0
        snapshot = db.scalar(select(SubscriptionSnapshot))
        assert snapshot.refund_available_at == datetime(
            9999, 12, 31, 23, 59, 59, tzinfo=UTC
        )
    page = client.get(API + "/me/subscriptions", headers=sh)
    assert page.status_code == 200, page.json()
    assert page.json()["issues"] == []
    assert page.json()["items"][0]["refund_available_at"] == "9999-12-31T23:59:59Z"
    detail = client.get(API + "/subscriptions/1", headers=sh)
    assert detail.status_code == 200, detail.json()
    assert detail.json()["refund_available_at"] == "9999-12-31T23:59:59Z"
