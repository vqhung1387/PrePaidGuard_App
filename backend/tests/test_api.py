from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import jwt
from eth_account import Account
from eth_account.messages import encode_defunct
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.db import lock
from app.models.entities import (
    AuthChallenge,
    EventRecord,
    SyncCursor,
    TransactionRecord,
)
from app.schemas.types import UINT_MAX, utcnow
from app.services.sync import run_scan, sync_through
from tests.fake_rpc import BASE_TIME, TOKEN

API = "/api/v1"


def test_default_log_windows_fit_public_fuji(harness):
    _, app, vault, rpc = harness
    rpc.head = 285
    settings = Settings(_env_file=None)
    assert run_scan(app.state.engine, vault, settings, max_batches=3) == (284, True)
    assert rpc.log_ranges == [(100, 189), (182, 279), (272, 284)]
    assert all(last - first + 1 <= 100 for first, last in rpc.log_ranges)


def signed_challenge(client, wallet):
    challenge = client.post(
        API + "/auth/challenge",
        json={
            "wallet_address": wallet.address,
            "chain_id": 43113,
        },
    )
    assert challenge.status_code == 201, challenge.json()
    fields = challenge.json()
    signature = wallet.sign_message(encode_defunct(text=fields["message"])).signature
    return {"challenge_id": fields["challenge_id"], "signature": "0x" + signature.hex()}


def login(client, wallet):
    response = client.post(API + "/auth/verify", json=signed_challenge(client, wallet))
    assert response.status_code == 200, response.json()
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def assert_error(response, status, code):
    assert response.status_code == status, response.json()
    error = response.json()["error"]
    assert error["code"] == code
    assert error["request_id"] == response.headers["X-Request-ID"]


def draft(client, headers, *, price="50000000", periods=2):
    return client.post(
        API + "/plan-drafts",
        headers=headers,
        json={
            "title": "Gym",
            "price_per_period": price,
            "total_periods": periods,
            "period_duration_seconds": 10,
            "grace_period_seconds": 20,
        },
    )


def test_wallet_session_replay_and_revocation(harness):
    client, app, _, _ = harness
    wallet = Account.create()
    assert_error(
        client.post(
            API + "/auth/challenge",
            json={
                "wallet_address": wallet.address,
                "chain_id": 1,
            },
        ),
        400,
        "UNSUPPORTED_CHAIN",
    )
    payload = signed_challenge(client, wallet)
    assert_error(
        client.post(
            API + "/auth/verify",
            json={
                **payload,
                "signature": "0x" + "00" * 65,
            },
        ),
        401,
        "INVALID_SIGNATURE",
    )
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda _: client.post(API + "/auth/verify", json=payload), range(2)
            )
        )
    assert sorted(result.status_code for result in results) == [200, 401]
    success = next(result for result in results if result.status_code == 200)
    rejected = next(result for result in results if result.status_code == 401)
    assert_error(rejected, 401, "CHALLENGE_USED")
    access_token = success.json()["access_token"]
    headers = {"Authorization": "Bearer " + access_token}
    claims = jwt.decode(access_token, options={"verify_signature": False})
    key = app.state.settings.access_token_secret.get_secret_value()
    for changes, code in (
        ({"exp": int(utcnow().timestamp()) - 1}, "TOKEN_EXPIRED"),
        ({"chain_id": 1}, "UNAUTHORIZED"),
    ):
        invalid = jwt.encode({**claims, **changes}, key, algorithm="HS256")
        assert_error(
            client.get(API + "/me", headers={"Authorization": "Bearer " + invalid}),
            401,
            code,
        )
    assert (
        client.get(API + "/me", headers=headers).json()["wallet_address"]
        == wallet.address.lower()
    )
    updated = client.patch(
        API + "/me", headers=headers, json={"display_name": " Thuận "}
    )
    assert updated.json()["display_name"] == "Thuận"
    assert client.post(API + "/auth/logout", headers=headers).status_code == 204
    assert_error(client.get(API + "/me", headers=headers), 401, "UNAUTHORIZED")
    expired = signed_challenge(client, wallet)
    with Session(app.state.engine) as db, db.begin():
        db.execute(
            update(AuthChallenge)
            .where(AuthChallenge.consumed_at.is_(None))
            .values(
                expires_at=utcnow() - timedelta(seconds=1),
            )
        )
    assert_error(
        client.post(API + "/auth/verify", json=expired), 401, "CHALLENGE_EXPIRED"
    )


def test_metadata_ownership_and_exact_amounts(harness):
    client, _, _, _ = harness
    a, b = login(client, Account.create()), login(client, Account.create())
    assert_error(draft(client, a), 403, "MERCHANT_REQUIRED")
    profile = client.post(API + "/merchants", headers=a, json={"business_name": "Gym"})
    assert profile.status_code == 201
    id_ = profile.json()["id"]
    assert client.get(f"{API}/merchants/{id_}").json() == profile.json()
    assert_error(
        client.patch(
            f"{API}/merchants/{id_}", headers=b, json={"business_name": "Other"}
        ),
        404,
        "NOT_FOUND",
    )
    assert_error(
        client.post(API + "/merchants", headers=a, json={"business_name": "Again"}),
        409,
        "MERCHANT_EXISTS",
    )
    assert (
        client.patch(
            f"{API}/merchants/{id_}", headers=a, json={"location_text": "Q1"}
        ).json()["location_text"]
        == "Q1"
    )
    assert_error(draft(client, a, price=1), 422, "VALIDATION_ERROR")
    assert_error(draft(client, a, price=str(UINT_MAX)), 422, "VALIDATION_ERROR")
    full = draft(client, a, price=str(UINT_MAX), periods=1)
    assert full.status_code == 201, full.json()
    assert full.json()["total_price"] == str(UINT_MAX)
    id_ = full.json()["id"]
    assert client.get(f"{API}/plan-drafts/{id_}", headers=a).json()[
        "price_per_period"
    ] == str(UINT_MAX)
    assert_error(client.get(f"{API}/plan-drafts/{id_}", headers=b), 404, "NOT_FOUND")
    assert_error(
        client.patch(f"{API}/plan-drafts/{id_}", headers=a, json={"total_periods": 2}),
        422,
        "VALIDATION_ERROR",
    )
    assert_error(
        client.patch(
            f"{API}/plan-drafts/{id_}", headers=a, json={"state": "PUBLISHED"}
        ),
        422,
        "VALIDATION_ERROR",
    )
    second = draft(client, a).json()
    page = client.get(API + "/plan-drafts", headers=a, params={"limit": 1}).json()
    assert [item["id"] for item in page["items"]] == [second["id"]]
    page2 = client.get(
        API + "/plan-drafts",
        headers=a,
        params={"limit": 1, "cursor": page["next_cursor"]},
    ).json()
    assert [item["id"] for item in page2["items"]] == [id_]
    assert_error(
        client.get(API + "/plan-drafts", headers=a, params={"cursor": "bad"}),
        422,
        "VALIDATION_ERROR",
    )


def test_filtered_plan_list_recovers_after_chain_reorg(harness):
    client, app, vault, rpc = harness
    original, replacement = Account.create().address, Account.create().address

    def list_for(wallet):
        return client.get(API + "/plans", params={"merchant_address": wallet})

    def mine_plan(tx_number, wallet, reference):
        plan = {
            "planId": 1,
            "merchant": wallet,
            "clientReference": reference,
            "token": TOKEN,
            "pricePerPeriod": 50_000_000,
            "totalPeriods": 2,
            "periodDuration": 10,
            "gracePeriod": 20,
        }
        rpc.plans[1] = plan
        rpc.add_tx(
            tx_number,
            100,
            wallet,
            "createPlan",
            [reference, TOKEN, 50_000_000, 2, 10, 20],
            event_name="PlanCreated",
            event_args=plan,
        )

    mine_plan(1, original, b"a" * 32)
    settings = app.state.settings
    assert run_scan(app.state.engine, vault, settings, max_batches=1) == (100, True)
    assert list_for(original).json()["items"][0]["merchant_address"] == original.lower()

    rpc.hashes[100] = "0x" + "de" * 32
    rpc.logs.clear()
    mine_plan(2, replacement, b"b" * 32)
    assert_error(list_for(original), 503, "RPC_UNAVAILABLE")

    rpc.plans.clear()
    assert_error(list_for(original), 503, "RPC_UNAVAILABLE")
    rpc.logs.clear()
    mine_plan(3, replacement, b"b" * 32)

    assert run_scan(app.state.engine, vault, settings, max_batches=1) == (100, True)
    assert list_for(original).json() == {"items": [], "next_cursor": None}
    assert (
        list_for(replacement).json()["items"][0]["merchant_address"]
        == replacement.lower()
    )


def test_retry_publication_after_correcting_draft_terms(harness):
    client, app, vault, rpc = harness
    merchant = Account.create()
    headers = login(client, merchant)
    assert (
        client.post(
            API + "/merchants", headers=headers, json={"business_name": "Gym"}
        ).status_code
        == 201
    )
    pending = draft(client, headers).json()
    path = f"{API}/plan-drafts/{pending['id']}"
    reference = bytes.fromhex(pending["client_reference"][2:])

    def create_plan(number, block):
        return rpc.add_tx(
            number,
            block,
            merchant.address,
            "createPlan",
            [reference, TOKEN, 50_000_000, 2, 10, 20],
            event_name="PlanCreated",
            event_args={
                "planId": number,
                "merchant": merchant.address,
                "clientReference": reference,
                "token": TOKEN,
                "pricePerPeriod": 50_000_000,
                "totalPeriods": 2,
                "periodDuration": 10,
                "gracePeriod": 20,
            },
        )

    def submit(hash_, draft_id=pending["id"], auth=headers):
        return client.post(
            API + "/transactions",
            headers=auth,
            json={"tx_hash": hash_, "action": "CREATE_PLAN", "plan_draft_id": draft_id},
        )

    def set_price(price):
        response = client.patch(path, headers=headers, json={"price_per_period": price})
        assert response.status_code == 200, response.json()

    tx = create_plan(1, 100)
    set_price("60000000")
    rpc.head = 120
    assert run_scan(app.state.engine, vault, app.state.settings, max_batches=3) == (
        119,
        True,
    )
    with Session(app.state.engine) as db:
        indexed_id = db.scalars(select(EventRecord.id)).one()

    assert_error(submit(tx), 409, "TX_MISMATCH")
    unchanged = client.get(path, headers=headers).json()
    assert unchanged["state"] == "DRAFT"
    assert unchanged["onchain_plan_id"] is None
    assert unchanged["price_per_period"] == "60000000"

    set_price("50000000")
    stranger = login(client, Account.create())
    assert_error(submit(tx, auth=stranger), 404, "NOT_FOUND")
    another_draft = draft(client, headers).json()
    assert_error(submit(tx, another_draft["id"]), 409, "TX_MISMATCH")

    with ThreadPoolExecutor(max_workers=2) as executor:
        retries = list(executor.map(submit, [tx, tx]))
    for response in retries:
        assert response.status_code == 202, response.json()
        assert response.json()["status"] == "CONFIRMED"
        assert response.json()["event_ids"] == [str(indexed_id)]
    assert retries[0].json() == retries[1].json()
    with Session(app.state.engine) as db:
        assert db.scalars(select(EventRecord.id)).one() == indexed_id
        assert db.scalars(select(TransactionRecord.tx_hash)).one() == tx

    published = client.get(path, headers=headers).json()
    assert published["state"] == "PUBLISHED"
    assert published["onchain_plan_id"] == "1"
    assert published["publication_tx_hash"] == tx

    other_tx = create_plan(2, 120)
    rpc.head = 121
    assert run_scan(app.state.engine, vault, app.state.settings, max_batches=1) == (
        120,
        True,
    )
    assert_error(submit(other_tx), 409, "TX_MISMATCH")
    assert client.get(path, headers=headers).json() == published


def test_chain_receipts_sync_and_live_boundaries(harness):
    client, app, vault, rpc = harness
    merchant, subscriber, stranger = (
        Account.create(),
        Account.create(),
        Account.create(),
    )
    mh, sh, xh = (
        login(client, merchant),
        login(client, subscriber),
        login(client, stranger),
    )
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json() == {"status": "ready"}
    assert (
        client.get(API + "/config").json()["rpc_url"] == "https://public.example.test"
    )
    assert (
        client.post(
            API + "/merchants", headers=mh, json={"business_name": "Gym"}
        ).status_code
        == 201
    )
    d = draft(client, mh).json()
    plan = {
        "planId": 1,
        "merchant": merchant.address,
        "clientReference": bytes.fromhex(d["client_reference"][2:]),
        "token": TOKEN,
        "pricePerPeriod": 50_000_000,
        "totalPeriods": 2,
        "periodDuration": 10,
        "gracePeriod": 20,
    }
    rpc.plans[1] = plan
    create = rpc.add_tx(
        1,
        100,
        merchant.address,
        "createPlan",
        [plan["clientReference"], TOKEN, 50_000_000, 2, 10, 20],
        event_name="PlanCreated",
        event_args=plan,
    )

    def submit(headers, hash_, action, **refs):
        return client.post(
            API + "/transactions",
            headers=headers,
            json={"tx_hash": hash_, "action": action, **refs},
        )

    published = submit(mh, create, "CREATE_PLAN", plan_draft_id=d["id"])
    assert published.status_code == 202, published.json()
    assert published.json()["status"] == "CONFIRMED"
    assert client.get(API + "/plans/1").json()["title"] == "Gym"
    assert (
        client.get(
            API + "/plans", params={"merchant_address": merchant.address}
        ).json()["items"][0]["total_price"]
        == "100000000"
    )
    assert_error(
        client.patch(
            f"{API}/plan-drafts/{d['id']}", headers=mh, json={"title": "Edited"}
        ),
        409,
        "PLAN_IMMUTABLE",
    )

    sub = {
        "subscriptionId": 5,
        "planId": 1,
        "subscriber": subscriber.address,
        "initialPrincipal": 100_000_000,
        "remainingPrincipal": 100_000_000,
        "completedPeriods": 0,
        "nonce": 0,
        "startedAt": BASE_TIME + 102,
        "nextReleaseAt": BASE_TIME + 112,
        "status": 0,
    }
    rpc.subs[5] = sub
    subscribed = {
        **{
            key: sub[key]
            for key in (
                "subscriptionId",
                "planId",
                "subscriber",
                "startedAt",
                "nextReleaseAt",
            )
        },
        "principal": 100_000_000,
    }
    invalid = rpc.add_tx(
        2,
        102,
        subscriber.address,
        "subscribe",
        [1],
        event_name="Subscribed",
        event_args=subscribed,
        emitter=TOKEN,
        add_to_index=False,
    )
    good = rpc.add_tx(
        3,
        102,
        subscriber.address,
        "subscribe",
        [1],
        event_name="Subscribed",
        event_args=subscribed,
    )
    wrong_contract = rpc.add_tx(
        4, 102, subscriber.address, "subscribe", [1], to=TOKEN, status=0
    )
    reverted = rpc.add_tx(5, 102, subscriber.address, "subscribe", [1], status=0)
    rpc.head = 102
    assert submit(sh, good, "SUBSCRIBE", plan_id="1").json()["status"] == "SUBMITTED"
    rpc.head = 103
    assert_error(submit(sh, invalid, "SUBSCRIBE", plan_id="1"), 409, "TX_MISMATCH")
    assert_error(
        submit(sh, wrong_contract, "SUBSCRIBE", plan_id="1"), 409, "TX_MISMATCH"
    )
    assert_error(submit(mh, reverted, "SUBSCRIBE", plan_id="1"), 409, "TX_MISMATCH")
    assert submit(sh, reverted, "SUBSCRIBE", plan_id="1").json()["status"] == "REVERTED"
    status = client.get(f"{API}/transactions/{good}", headers=sh).json()
    assert status["status"] == "CONFIRMED"
    assert len(status["event_ids"]) == 1
    assert (
        submit(sh, good, "SUBSCRIBE", plan_id="1").json()["event_ids"]
        == status["event_ids"]
    )
    assert_error(
        submit(sh, good, "SUBSCRIBE", plan_id="2"), 409, "TRANSACTION_CONFLICT"
    )
    assert_error(client.get(f"{API}/transactions/{good}", headers=xh), 404, "NOT_FOUND")
    assert_error(client.get(f"{API}/subscriptions/5", headers=xh), 404, "NOT_FOUND")
    assert_error(
        client.get(f"{API}/subscriptions/5/events", headers=xh), 404, "NOT_FOUND"
    )
    assert (
        client.get(API + "/me/subscriptions", headers=sh).json()["items"][0]["sync"][
            "source"
        ]
        == "PROJECTION"
    )
    assert client.get(API + "/me/subscriptions", headers=xh).json()["items"] == []
    assert (
        client.get(
            API + "/merchant/subscriptions", headers=mh, params={"plan_id": "1"}
        ).json()["items"][0]["subscription_id"]
        == "5"
    )
    url = f"{API}/subscriptions/5/eligibility"
    assert client.get(url, headers=sh).json()["reasons"] == ["TOO_EARLY"]
    rpc.timestamps[103] = sub["nextReleaseAt"]
    assert client.get(url, headers=mh).json()["can_check_in"]
    rpc.timestamps[103] = sub["nextReleaseAt"] + 20
    allowed = client.get(url, headers=sh).json()
    assert allowed["can_refund"] and not allowed["can_check_in"]

    payout = {
        "subscriptionId": 5,
        "planId": 1,
        "principal": 50_000_000,
        "merchantYield": 7,
        "subscriberYield": 2,
        "platformYield": 1,
        "nonceAfter": 1,
    }
    check_in = rpc.add_tx(
        6,
        104,
        merchant.address,
        "checkInWithSignature",
        [(5, merchant.address, 1, 0, BASE_TIME + 140), b"\0" * 65],
        event_name="PeriodReleased",
        event_args={
            **payout,
            "periodIndex": 1,
            "nextReleaseAt": BASE_TIME + 130,
            "completed": False,
        },
    )
    rpc.subs[5] = {
        **sub,
        "remainingPrincipal": 50_000_000,
        "completedPeriods": 1,
        "nonce": 1,
        "nextReleaseAt": BASE_TIME + 130,
    }
    rpc.head = 104
    rpc.subs_by_block[103] = {5: sub}
    pending = client.get(f"{API}/subscriptions/5", headers=sh)
    assert pending.status_code == 200, pending.json()
    assert pending.json()["remaining_principal"] == "100000000"
    assert pending.json()["sync"]["block_number"] == "103"
    latest = client.get(url, headers=mh).json()
    assert (latest["nonce"], latest["sync"]["block_number"]) == ("1", "104")

    rpc.head = 105
    # No POST for the release. Scanning with an overlapping range restores history.
    with Session(app.state.engine) as db, db.begin():
        lock(db, vault.lock_key)
        assert sync_through(
            db, vault, app.state.settings, rpc.vault.checked_head(), 104, max_batches=2
        )
        assert db.scalar(select(func.count()).select_from(EventRecord)) == 3
    confirmed = submit(mh, check_in, "CHECK_IN", subscription_id="5")
    assert confirmed.status_code == 202, confirmed.json()
    assert confirmed.json()["status"] == "CONFIRMED"
    view = client.get(f"{API}/subscriptions/5", headers=sh)
    assert view.status_code == 200, view.json()
    assert view.json()["yield_summary"] == {
        "mode": "MOCK",
        "estimated_unclaimed": "17",
        "paid_merchant": "7",
        "paid_subscriber": "2",
        "paid_platform": "1",
    }
    rpc.head = 106
    refund = rpc.add_tx(
        7,
        106,
        subscriber.address,
        "refund",
        [5],
        event_name="Refunded",
        event_args={**payout, "nonceAfter": 2},
    )
    rpc.subs_by_block[105] = {5: rpc.subs[5]}
    rpc.subs[5] = {**rpc.subs[5], "remainingPrincipal": 0, "status": 2, "nonce": 2}
    assert (
        submit(sh, refund, "REFUND", subscription_id="5").json()["status"]
        == "SUBMITTED"
    )
    prior = client.get(f"{API}/subscriptions/5", headers=sh).json()
    assert (prior["status"], prior["remaining_principal"]) == ("ACTIVE", "50000000")
    assert client.get(url, headers=sh).json()["reasons"] == ["TERMINAL_STATE"]

    rpc.head = 107
    assert (
        submit(sh, refund, "REFUND", subscription_id="5").json()["status"]
        == "CONFIRMED"
    )
    final = client.get(f"{API}/subscriptions/5", headers=sh).json()
    assert (
        final["principal_released"],
        final["principal_refunded"],
        final["remaining_principal"],
    ) == ("50000000", "50000000", "0")
    assert final["next_release_at"] is None and final["refund_available_at"] is None
    assert client.get(url, headers=sh).json()["reasons"] == ["TERMINAL_STATE"]
    events = client.get(f"{API}/subscriptions/5/events", headers=mh).json()["items"]
    assert [event["event_name"] for event in events] == [
        "REFUNDED",
        "PERIOD_RELEASED",
        "SUBSCRIBED",
    ]
    assert events[1]["payload"]["principal"] == "50000000"

    rpc.outage = True
    assert_error(client.get(url, headers=sh), 503, "RPC_UNAVAILABLE")
    assert_error(
        client.get(f"{API}/transactions/{good}", headers=sh), 503, "RPC_UNAVAILABLE"
    )
    with Session(app.state.engine) as db:
        assert (
            db.scalar(select(TransactionRecord.status).filter_by(tx_hash=good))
            == "CONFIRMED"
        )
        assert db.scalar(select(SyncCursor.last_processed_block)) == 106

    rpc.outage = False
    rpc.hashes[106] = "0x" + "de" * 32
    rpc.logs = [log for log in rpc.logs if log["transactionHash"] != refund]
    del rpc.transactions[refund]
    del rpc.receipts[refund]
    rpc.subs[5] = {
        **rpc.subs[5],
        "remainingPrincipal": 50_000_000,
        "status": 0,
        "nonce": 1,
    }
    with Session(app.state.engine) as db, db.begin():
        lock(db, vault.lock_key)
        assert sync_through(
            db, vault, app.state.settings, vault.checked_head(), 106, max_batches=2
        )
        assert db.scalar(select(func.count()).select_from(EventRecord)) == 3
    assert (
        client.get(f"{API}/transactions/{refund}", headers=sh).json()["status"]
        == "SUBMITTED"
    )
    assert client.get(f"{API}/subscriptions/5", headers=sh).json()["status"] == "ACTIVE"


def test_schema_and_no_secret_in_validation(harness):
    client, _, _, rpc = harness
    schema = client.get("/openapi.json").json()
    operations = [op for path in schema["paths"].values() for op in path.values()]
    assert len(operations) == 24
    assert "HTTPBearer" in schema["components"]["securitySchemes"]
    assert (
        schema["components"]["schemas"]["PlanTerms"]["properties"]["price_per_period"][
            "type"
        ]
        == "string"
    )
    assert schema["paths"][API + "/transactions"]["post"]["responses"]["422"][
        "content"
    ]["application/json"]["schema"]["$ref"].endswith("/ErrorResponse")
    response = client.post(
        API + "/auth/verify", json={"challenge_id": "hidden", "signature": "secret"}
    )
    assert_error(response, 422, "VALIDATION_ERROR")
    assert "secret" not in response.text and "hidden" not in response.text
    rpc.chain_id = 1
    assert_error(client.get("/ready"), 503, "CONFIG_MISMATCH")
