import json
import os
from pathlib import Path

import pytest
from eth_account import Account
from eth_account.messages import encode_defunct
from sqlalchemy import select
from sqlalchemy.orm import Session
from web3 import Web3

from app.blockchain.vault import Vault
from app.core.config import Settings
from app.models.entities import TransactionRecord


@pytest.mark.skipif(
    not os.environ.get("CONTRACT_TEST_RPC"), reason="Requires isolated local EVM"
)
@pytest.mark.parametrize("cancel", [True, False])
@pytest.mark.parametrize("legacy", [True, False])
def test_confirmed_cancel_and_speedup(harness, tmp_path, cancel, legacy):
    client, app, _, _ = harness
    rpc = os.environ["CONTRACT_TEST_RPC"]
    w3 = Web3(Web3.HTTPProvider(rpc))
    assert w3.eth.chain_id == 31337
    root = Path(__file__).resolve().parents[2]
    funder, merchant, treasury = w3.eth.accounts[:3]
    customer = Account.create()

    def deploy(name, source, args):
        a = json.loads(
            (
                root / f"contracts/artifacts/contracts/{source}.sol/{name}.json"
            ).read_text()
        )
        r = w3.eth.wait_for_transaction_receipt(
            w3.eth.contract(abi=a["abi"], bytecode=a["bytecode"])
            .constructor(*args)
            .transact({"from": funder})
        )
        assert r.status == 1
        return w3.eth.contract(address=r.contractAddress, abi=a["abi"]), r

    token, _ = deploy("MockUSDC", "mocks/MockUSDC", [funder])
    vault, receipt = deploy(
        "PrepaidVault", "PrepaidVault", [token.address, treasury, "0x" + "00" * 20]
    )
    for tx in [
        vault.functions.createPlan(b"x" * 32, token.address, 10, 2, 10, 20).transact(
            {"from": merchant}
        ),
        token.functions.mint(customer.address, 100).transact({"from": funder}),
        w3.eth.send_transaction(
            {"from": funder, "to": customer.address, "value": 10**18}
        ),
    ]:
        assert w3.eth.wait_for_transaction_receipt(tx).status == 1

    signed_bytes = {}

    def send_signed(tx):
        signed = customer.sign_transaction(tx)
        tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
        signed_bytes[Web3.to_hex(tx_hash)] = Web3.to_hex(signed.raw_transaction)
        return tx_hash

    approval = token.functions.approve(vault.address, 100).build_transaction(
        {
            "from": customer.address,
            "chainId": 31337,
            "nonce": 0,
            "gas": 100000,
            "gasPrice": 10**10,
        }
    )
    assert w3.eth.wait_for_transaction_receipt(send_signed(approval)).status == 1
    manifest = {
        "deployment_id": "audit-cancel-" + vault.address,
        "chain_id": 31337,
        "chain_name": "Local",
        "public_rpc_url": rpc,
        "explorer_url": rpc,
        "vault_address": vault.address,
        "token": {"address": token.address},
        "abi_version": "prepaidguard-1",
        "deployment_block": receipt.blockNumber,
        "yield_mode": "DISABLED",
        "confirmations": 1,
        "subscription_status_codes": {"active": 1, "completed": 2, "refunded": 3},
    }
    path = tmp_path / "cancel-deployment.json"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    settings = Settings(
        chain_id=31337,
        deployment_file=path,
        abi_file=root / "shared/abi/PrepaidVault.json",
        rpc_url=rpc,
        access_token_secret="local-audit-cancellation-" * 3,
    )
    app.state.settings = settings
    app.state.vault = Vault(settings)
    challenge = client.post(
        "/api/v1/auth/challenge",
        json={"wallet_address": customer.address, "chain_id": 31337},
    ).json()
    signature = customer.sign_message(
        encode_defunct(text=challenge["message"])
    ).signature
    auth = client.post(
        "/api/v1/auth/verify",
        json={
            "challenge_id": challenge["challenge_id"],
            "signature": Web3.to_hex(signature),
        },
    )
    assert auth.status_code == 200, auth.json()
    headers = {"Authorization": "Bearer " + auth.json()["access_token"]}
    w3.provider.make_request("evm_setAutomine", [False])
    try:
        original = send_signed(
            vault.functions.subscribe(1).build_transaction(
                {
                    "from": customer.address,
                    "nonce": 1,
                    "chainId": 31337,
                    "gas": 300000,
                    "gasPrice": 10**10,
                }
            )
        )
        tracked = client.post(
            "/api/v1/transactions",
            headers=headers,
            json={
                "tx_hash": Web3.to_hex(original),
                "action": "SUBSCRIBE",
                "plan_id": "1",
            },
        )
        assert tracked.status_code == 202, tracked.json()
        assert tracked.json()["status"] == "SUBMITTED"
        replacement_tx = {
            "from": customer.address,
            "to": customer.address,
            "value": 0,
            "nonce": 1,
            "chainId": 31337,
            "gas": 21000,
            "gasPrice": 2 * 10**10,
        }
        if not cancel:
            replacement_tx = vault.functions.subscribe(1).build_transaction(
                {
                    "from": customer.address,
                    "nonce": 1,
                    "chainId": 31337,
                    "gas": 300000,
                    "gasPrice": 2 * 10**10,
                }
            )
        replacement = send_signed(replacement_tx)
        w3.provider.make_request("evm_mine", [])
    finally:
        w3.provider.make_request("evm_setAutomine", [True])
    assert w3.eth.wait_for_transaction_receipt(replacement).status == 1
    assert w3.eth.get_transaction_count(customer.address) == 2
    assert vault.functions.subscriptionCount().call() == (0 if cancel else 1)
    if legacy:
        with Session(app.state.engine) as db, db.begin():
            record = db.scalar(
                select(TransactionRecord).where(
                    TransactionRecord.tx_hash == Web3.to_hex(original)
                )
            )
            record.sender_nonce = None
    response = client.post(
        "/api/v1/transactions/" + Web3.to_hex(original) + "/replacement",
        headers=headers,
        json={
            "tx_hash": Web3.to_hex(replacement),
            **(
                {"original_signed_transaction": signed_bytes[Web3.to_hex(original)]}
                if legacy
                else {}
            ),
        },
    )
    assert response.status_code == 200, response.json()
    assert response.json()["original"]["status"] == (
        "CANCELLED" if cancel else "REPLACED"
    )
    if cancel:
        assert response.json()["replacement"] is None
        retry = send_signed(
            vault.functions.subscribe(1).build_transaction(
                {
                    "from": customer.address,
                    "nonce": 2,
                    "chainId": 31337,
                    "gas": 300000,
                    "gasPrice": 10**10,
                }
            )
        )
        assert w3.eth.wait_for_transaction_receipt(retry).status == 1
        response = client.post(
            "/api/v1/transactions",
            headers=headers,
            json={"tx_hash": Web3.to_hex(retry), "action": "SUBSCRIBE", "plan_id": "1"},
        )
        assert response.json()["status"] == "CONFIRMED", response.json()
        assert vault.functions.subscriptionCount().call() == 1
    else:
        assert response.json()["replacement"]["status"] == "CONFIRMED"
