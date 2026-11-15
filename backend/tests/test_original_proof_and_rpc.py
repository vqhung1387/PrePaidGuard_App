import threading
import time

import pytest
from eth_account import Account
from sqlalchemy import select
from sqlalchemy.orm import Session
from web3 import Web3

from app.core.errors import ApiError, rpc_error
from app.models.entities import TransactionRecord
from tests.fake_rpc import VAULT
from tests.test_api import login


def signed_original(wallet, kind, chain=43113):
    data = Web3.to_hex(Web3.keccak(text="subscribe(uint256)")[:4]) + f"{1:064x}"
    fields = {
        "to": VAULT,
        "nonce": 201,
        "gas": 200000,
        "value": 0,
        "data": data,
        "chainId": chain,
    }
    if kind == 0:
        fields["gasPrice"] = 1_000_000_000
    elif kind == 1:
        fields.update(type=1, gasPrice=1_000_000_000, accessList=[])
    else:
        fields.update(
            type=2, maxFeePerGas=2_000_000_000, maxPriorityFeePerGas=1_000_000_000
        )
    return wallet.sign_transaction(fields)


@pytest.mark.parametrize("kind", [0, 1, 2])
def test_signed_original_recovers_a_dropped_legacy_nonce(harness, kind):
    client, app, _, rpc = harness
    wallet = Account.create()
    headers = login(client, wallet)
    signed = signed_original(wallet, kind)
    original = Web3.to_hex(signed.hash)
    result = client.post(
        "/api/v1/transactions",
        headers=headers,
        json={"tx_hash": original, "action": "SUBSCRIBE", "plan_id": "1"},
    )
    assert result.status_code == 202
    assert result.json()["sender_nonce"] is None
    replacement = rpc.add_tx(
        202, 101, wallet.address, "subscribe", [1], to=wallet.address
    )
    rpc.transactions[replacement].update(nonce=hex(201), input="0x", value="0x0")
    rpc.head = 104
    raw = Web3.to_hex(signed.raw_transaction)
    proof = client.post(
        "/api/v1/transactions/original-proof",
        headers=headers,
        json={"tx_hash": original, "original_signed_transaction": raw},
    )
    assert proof.status_code == 200, proof.json()
    assert proof.json()["sender_nonce"] == "201"
    result = client.post(
        "/api/v1/transactions/" + original + "/replacement",
        headers=headers,
        json={"tx_hash": replacement, "original_signed_transaction": raw},
    )
    assert result.status_code == 200, result.json()
    assert result.json()["original"]["status"] == "CANCELLED"
    with Session(app.state.engine) as db:
        record = db.scalar(
            select(TransactionRecord).where(TransactionRecord.tx_hash == original)
        )
        assert record.sender_nonce == 201
        assert not hasattr(record, "original_signed_transaction")


@pytest.mark.parametrize("change", ["hash", "owner", "chain", "invalid", "too_long"])
def test_wrong_original_proof_never_releases_pending(harness, change):
    client, _, _, _ = harness
    wallet = Account.create()
    signed = signed_original(wallet, 2, chain=1 if change == "chain" else 43113)
    headers = login(client, Account.create() if change == "owner" else wallet)
    original = Web3.to_hex(signed.hash)
    if change == "hash":
        original = "0x" + "aa" * 32
    raw = Web3.to_hex(signed.raw_transaction)
    if change == "invalid":
        raw = "0xdeadbeef"
        original = Web3.to_hex(Web3.keccak(bytes.fromhex("deadbeef")))
    if change == "too_long":
        raw = "0x" + "00" * 20000
    response = client.post(
        "/api/v1/transactions/original-proof",
        headers=headers,
        json={"tx_hash": original, "original_signed_transaction": raw},
    )
    assert response.status_code in {409, 422}
    assert raw not in response.text
    assert wallet.key.hex() not in response.text


def test_plan_rpc_reads_are_bounded_parallel_and_keep_order(harness, monkeypatch):
    _, _, vault, _ = harness
    active = peak = 0
    mutex = threading.Lock()

    def read_plan(id_, block):
        nonlocal active, peak
        with mutex:
            active += 1
            peak = max(peak, active)
        time.sleep(0.03 if id_ % 2 else 0.06)
        with mutex:
            active -= 1
        return {"planId": id_}

    monkeypatch.setattr(vault, "plan", read_plan)
    ids = list(range(20))
    result = vault.plans(ids, vault.confirmed_block())
    assert [value["planId"] for value in result] == ids
    assert 2 <= peak <= 4


def test_unprotected_legacy_signature_cannot_prove_the_chain(harness):
    client, _, _, _ = harness
    wallet = Account.create()
    signed = wallet.sign_transaction(
        {"to": VAULT, "nonce": 201, "gas": 21000, "value": 0, "gasPrice": 1_000_000_000}
    )
    response = client.post(
        "/api/v1/transactions/original-proof",
        headers=login(client, wallet),
        json={
            "tx_hash": Web3.to_hex(signed.hash),
            "original_signed_transaction": Web3.to_hex(signed.raw_transaction),
        },
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "INVALID_ORIGINAL_TRANSACTION"


def test_plan_reads_fail_without_returning_partial_or_cached_data(harness, monkeypatch):
    _, _, vault, _ = harness

    def unavailable(id_, block):
        if id_ == 1:
            raise rpc_error()
        return {"planId": id_}

    monkeypatch.setattr(vault, "plan", unavailable)
    with pytest.raises(ApiError) as error:
        vault.plans([0, 1, 2, 3], vault.confirmed_block())
    assert error.value.code == "RPC_UNAVAILABLE"
