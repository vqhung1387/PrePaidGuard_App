import pytest
from eth_account import Account
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import ApiError
from app.models.entities import EventRecord, SyncCursor
from app.services.sync import run_scan
from tests.fake_rpc import TOKEN, VAULT
from tests.test_api import API, assert_error, draft, login
from tests.test_replacements import pending_and_cancel


@pytest.mark.parametrize(
    "log",
    [
        {"topics": []},
        {"address": VAULT},
        {"address": None, "topics": []},
        {"address": VAULT, "topics": []},
        {"address": TOKEN, "topics": []},
        {"address": VAULT, "topics": ["0x" + "aa" * 32]},
    ],
)
def test_incomplete_rpc_log_fails_as_rpc_error_and_scan_can_recover(harness, log):
    _, app, vault, rpc = harness
    rpc.logs.append({"blockNumber": "0x64", **log})
    with pytest.raises(ApiError) as caught:
        run_scan(app.state.engine, vault, app.state.settings, max_batches=1)
    assert caught.value.code == "RPC_UNAVAILABLE"
    with Session(app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(EventRecord)) == 0
        assert db.scalar(select(func.count()).select_from(SyncCursor)) == 0
    rpc.logs.clear()
    assert run_scan(app.state.engine, vault, app.state.settings, max_batches=1) == (
        100,
        True,
    )


def test_projection_rebuild_clears_orphaned_replacement_proof(harness):
    client, _, headers, original, replacement = pending_and_cancel(harness)
    response = client.post(
        API + "/transactions/" + original + "/replacement",
        headers=headers,
        json={"tx_hash": replacement},
    )
    assert response.status_code == 200
    assert response.json()["original"]["status"] == "CANCELLED"
    assert run_scan(
        harness[1].state.engine,
        harness[2],
        harness[1].state.settings,
        max_batches=1,
        rebuild=True,
    ) == (103, True)
    reopened = client.get(API + "/transactions/" + original, headers=headers)
    assert reopened.status_code == 200
    assert reopened.json()["status"] == "SUBMITTED"
    assert reopened.json()["replacement_tx_hash"] is None
    assert reopened.json()["sender_nonce"] == "201"


@pytest.mark.parametrize("field", ["business_name", "description", "location_text"])
def test_merchant_rejects_text_that_postgres_cannot_store(harness, field):
    client, _, _, _ = harness
    headers = login(client, Account.create())
    response = client.post(
        API + "/merchants",
        headers=headers,
        json={"business_name": "Gym", field: "bad\x00text"},
    )
    assert_error(response, 422, "VALIDATION_ERROR")
    assert (
        client.post(
            API + "/merchants", headers=headers, json={"business_name": "Valid Gym"}
        ).status_code
        == 201
    )


def test_display_name_rejects_nul_without_reporting_database_outage(harness):
    client, _, _, _ = harness
    headers = login(client, Account.create())
    assert_error(
        client.patch(
            API + "/me", headers=headers, json={"display_name": "bad\x00name"}
        ),
        422,
        "VALIDATION_ERROR",
    )


@pytest.mark.parametrize("field", ["title", "description"])
def test_plan_text_is_validated_on_create_and_patch(harness, field):
    client, _, _, _ = harness
    headers = login(client, Account.create())
    assert (
        client.post(
            API + "/merchants", headers=headers, json={"business_name": "Gym"}
        ).status_code
        == 201
    )
    created = draft(client, headers).json()
    terms = {
        name: created[name]
        for name in (
            "title",
            "description",
            "price_per_period",
            "total_periods",
            "period_duration_seconds",
            "grace_period_seconds",
        )
    }
    assert_error(
        client.post(
            API + "/plan-drafts", headers=headers, json={**terms, field: "bad\x00text"}
        ),
        422,
        "VALIDATION_ERROR",
    )
    path = API + "/plan-drafts/" + created["id"]
    assert_error(
        client.patch(path, headers=headers, json={field: "bad\x00text"}),
        422,
        "VALIDATION_ERROR",
    )
    assert client.get(path, headers=headers).json()[field] == created[field]


def test_unicode_emoji_and_multiline_metadata_still_work(harness):
    client, _, _, _ = harness
    headers = login(client, Account.create())
    fields = {
        "business_name": "  Phòng tập 🏋️ Đà Nẵng  ",
        "description": "Đăng ký\nGiải ngân từng kỳ",
        "location_text": None,
    }
    response = client.post(API + "/merchants", headers=headers, json=fields)
    assert response.status_code == 201
    assert response.json()["business_name"] == fields["business_name"].strip()
    assert response.json()["description"] == fields["description"]
    assert response.json()["location_text"] is None
