import pytest
from eth_account import Account

from tests.test_api import login

API = "/api/v1"


def pending_and_cancel(harness):
    client, _, _, rpc = harness
    wallet = Account.create()
    headers = login(client, wallet)
    original = rpc.add_tx(201, 100, wallet.address, "subscribe", [1])
    rpc.receipts.pop(original)
    response = client.post(
        API + "/transactions",
        headers=headers,
        json={"tx_hash": original, "action": "SUBSCRIBE", "plan_id": "1"},
    )
    assert response.status_code == 202, response.json()
    assert response.json()["sender_nonce"] == "201"
    rpc.transactions.pop(original)
    replacement = rpc.add_tx(
        202, 101, wallet.address, "subscribe", [1], to=wallet.address
    )
    rpc.transactions[replacement].update(nonce=hex(201), input="0x", value="0x0")
    rpc.head = 104
    return client, rpc, headers, original, replacement


def test_confirmed_cancel_is_idempotent_and_releases_old_pending(harness):
    client, _, headers, original, replacement = pending_and_cancel(harness)
    path = API + "/transactions/" + original + "/replacement"
    for _ in range(2):
        response = client.post(path, headers=headers, json={"tx_hash": replacement})
        assert response.status_code == 200, response.json()
        assert response.json()["original"]["status"] == "CANCELLED"
        assert response.json()["original"]["replacement_tx_hash"] == replacement
        assert response.json()["replacement"] is None
    assert (
        client.get(API + "/transactions/" + original, headers=headers).json()["status"]
        == "CANCELLED"
    )


@pytest.mark.parametrize(
    "change,code",
    [
        ("nonce", "TX_MISMATCH"),
        ("sender", "TX_MISMATCH"),
        ("pending", "REPLACEMENT_NOT_CONFIRMED"),
        ("confirmations", "REPLACEMENT_NOT_CONFIRMED"),
        ("block", "RPC_UNAVAILABLE"),
    ],
)
def test_invalid_replacements_never_unblock_original(harness, change, code):
    client, rpc, headers, original, replacement = pending_and_cancel(harness)
    if change == "nonce":
        rpc.transactions[replacement]["nonce"] = "0x999"
    elif change == "sender":
        rpc.transactions[replacement]["from"] = Account.create().address
    elif change == "pending":
        rpc.receipts.pop(replacement)
    elif change == "confirmations":
        rpc.head = 101
    else:
        rpc.receipts[replacement]["blockHash"] = "0x" + "dd" * 32
    response = client.post(
        API + "/transactions/" + original + "/replacement",
        headers=headers,
        json={"tx_hash": replacement},
    )
    assert response.status_code in {409, 503}, response.json()
    assert response.json()["error"]["code"] == code
    assert (
        client.get(API + "/transactions/" + original, headers=headers).json()["status"]
        == "SUBMITTED"
    )


def test_replacement_endpoint_requires_original_owner(harness):
    client, _, _, original, replacement = pending_and_cancel(harness)
    outsider = login(client, Account.create())
    response = client.post(
        API + "/transactions/" + original + "/replacement",
        headers=outsider,
        json={"tx_hash": replacement},
    )
    assert response.status_code == 404


def test_legacy_nonce_cannot_be_guessed_and_cancel_reorg_reopens_pending(harness):
    from sqlalchemy import select
    from sqlalchemy.orm import Session

    from app.models.entities import TransactionRecord

    client, rpc, headers, original, replacement = pending_and_cancel(harness)
    path = API + "/transactions/" + original + "/replacement"
    assert (
        client.post(path, headers=headers, json={"tx_hash": replacement}).status_code
        == 200
    )
    rpc.hashes[101] = "0x" + "ef" * 32
    status = client.get(API + "/transactions/" + original, headers=headers)
    assert status.json()["status"] == "SUBMITTED"
    assert status.json()["replacement_tx_hash"] is None
    with Session(harness[1].state.engine) as db, db.begin():
        record = db.scalar(
            select(TransactionRecord).where(TransactionRecord.tx_hash == original)
        )
        record.sender_nonce = None
    response = client.post(path, headers=headers, json={"tx_hash": replacement})
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "ORIGINAL_TX_UNAVAILABLE"
