import json
import os
from pathlib import Path
from urllib.parse import urlsplit
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from eth_account import Account
from eth_account.messages import encode_defunct, encode_typed_data
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from web3 import Web3

from app.blockchain.vault import Vault
from app.core.config import Settings
from app.main import create_app
from app.services.sync import run_scan

ROOT = Path(__file__).resolve().parents[2]
API = "/api/v1"


@pytest.mark.skipif(
    not os.environ.get("CONTRACT_TEST_RPC") or not os.environ.get("TEST_DATABASE_URL"),
    reason="Requires a local EVM node, compiled contracts and PostgreSQL",
)
@pytest.mark.parametrize("yield_mode", ["DISABLED", "MOCK"])
def test_real_vault_receipts_and_api(tmp_path, monkeypatch, yield_mode):
    rpc = os.environ["CONTRACT_TEST_RPC"]
    assert urlsplit(rpc).hostname in {"localhost", "127.0.0.1"}
    w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 8}))
    assert w3.eth.chain_id == 31337
    funder = w3.eth.accounts[0]
    treasury = w3.eth.accounts[3]
    merchant, customer = Account.create(), Account.create()

    def deploy(name, source, args):
        artifact = json.loads(
            (
                ROOT / f"contracts/artifacts/contracts/{source}.sol/{name}.json"
            ).read_text(encoding="utf-8")
        )
        factory = w3.eth.contract(abi=artifact["abi"], bytecode=artifact["bytecode"])
        receipt = w3.eth.wait_for_transaction_receipt(
            factory.constructor(*args).transact({"from": funder})
        )
        assert receipt.status == 1
        return w3.eth.contract(
            address=receipt.contractAddress, abi=artifact["abi"]
        ), receipt

    def send(fn, wallet, expected=1):
        tx = fn.build_transaction(
            {
                "from": wallet.address,
                "nonce": w3.eth.get_transaction_count(wallet.address),
                "chainId": 31337,
                "gas": 800_000,
                "gasPrice": w3.eth.gas_price,
            }
        )
        receipt = w3.eth.wait_for_transaction_receipt(
            w3.eth.send_raw_transaction(wallet.sign_transaction(tx).raw_transaction)
        )
        assert receipt.status == expected
        return Web3.to_hex(receipt.transactionHash)

    def advance(seconds):
        for method, params in [("evm_increaseTime", [seconds]), ("evm_mine", [])]:
            assert "error" not in w3.provider.make_request(method, params)

    def check(response, status):
        assert response.status_code == status, response.json()
        return response.json()

    for wallet in (merchant, customer):
        w3.eth.wait_for_transaction_receipt(
            w3.eth.send_transaction(
                {"from": funder, "to": wallet.address, "value": w3.to_wei(1, "ether")}
            )
        )
    token, _ = deploy("MockUSDC", "mocks/MockUSDC", [funder])
    adapter = None
    if yield_mode == "MOCK":
        adapter, _ = deploy(
            "MockYieldAdapter", "mocks/MockYieldAdapter", [token.address, funder]
        )
    contract, receipt = deploy(
        "PrepaidVault",
        "PrepaidVault",
        [token.address, treasury, adapter.address if adapter else "0x" + "00" * 20],
    )
    if adapter:
        w3.eth.wait_for_transaction_receipt(
            adapter.functions.bindVault(contract.address).transact({"from": funder})
        )
    w3.eth.wait_for_transaction_receipt(
        token.functions.mint(customer.address, 200_000_000).transact({"from": funder})
    )
    manifest = tmp_path / "deployment.json"
    manifest.write_text(
        json.dumps(
            {
                "deployment_id": "local-contract-" + contract.address,
                "chain_id": 31337,
                "chain_name": "Local",
                "public_rpc_url": rpc,
                "explorer_url": rpc,
                "vault_address": contract.address,
                "token": {"address": token.address},
                "abi_version": "prepaidguard-1",
                "deployment_block": receipt.blockNumber,
                "yield_mode": yield_mode,
                "confirmations": 1,
                "subscription_status_codes": {
                    "active": 1,
                    "completed": 2,
                    "refunded": 3,
                },
            }
        ),
        encoding="utf-8",
    )
    db_url = make_url(os.environ["TEST_DATABASE_URL"])
    schema = "pp_chain_" + uuid4().hex
    admin = create_engine(db_url)
    with admin.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    try:
        monkeypatch.setenv(
            "DATABASE_URL",
            db_url.update_query_dict(
                {"options": f"-csearch_path={schema}"}
            ).render_as_string(hide_password=False),
        )
        command.upgrade(Config("alembic.ini"), "head")
        settings = Settings(
            chain_id=31337,
            deployment_file=manifest,
            abi_file=ROOT / "shared/abi/PrepaidVault.json",
            access_token_secret="local-contract-test-" * 3,
        )
        vault = Vault(settings)
        app = create_app(settings, vault)
        with TestClient(app) as client:
            assert check(client.get("/ready"), 200)["status"] == "ready"
            assert check(client.get(API + "/config"), 200)["yield_mode"] == yield_mode

            def login(wallet):
                challenge = check(
                    client.post(
                        API + "/auth/challenge",
                        json={"wallet_address": wallet.address, "chain_id": 31337},
                    ),
                    201,
                )
                signature = wallet.sign_message(
                    encode_defunct(text=challenge["message"])
                ).signature
                session = check(
                    client.post(
                        API + "/auth/verify",
                        json={
                            "challenge_id": challenge["challenge_id"],
                            "signature": Web3.to_hex(signature),
                        },
                    ),
                    200,
                )
                return {"Authorization": "Bearer " + session["access_token"]}

            mh, ch = login(merchant), login(customer)
            check(
                client.post(
                    API + "/merchants", headers=mh, json={"business_name": "Gym"}
                ),
                201,
            )
            draft = check(
                client.post(
                    API + "/plan-drafts",
                    headers=mh,
                    json={
                        "title": "Real contract",
                        "price_per_period": "50000000",
                        "total_periods": 2,
                        "period_duration_seconds": 60,
                        "grace_period_seconds": 120,
                    },
                ),
                201,
            )

            def track(tx_hash, action, headers, expected="CONFIRMED", **refs):
                value = check(
                    client.post(
                        API + "/transactions",
                        headers=headers,
                        json={"tx_hash": tx_hash, "action": action, **refs},
                    ),
                    202,
                )
                assert value["status"] == expected
                assert len(value["event_ids"]) == (expected == "CONFIRMED")
                return value

            published = send(
                contract.functions.createPlan(
                    draft["client_reference"], token.address, 50_000_000, 2, 60, 120
                ),
                merchant,
            )
            path = f"{API}/plan-drafts/{draft['id']}"
            check(
                client.patch(path, headers=mh, json={"price_per_period": "60000000"}),
                200,
            )
            advance(1)
            assert run_scan(app.state.engine, vault, settings, max_batches=10)[1]
            mismatch = client.post(
                API + "/transactions",
                headers=mh,
                json={
                    "tx_hash": published,
                    "action": "CREATE_PLAN",
                    "plan_draft_id": draft["id"],
                },
            )
            assert check(mismatch, 409)["error"]["code"] == "TX_MISMATCH"
            check(
                client.patch(path, headers=mh, json={"price_per_period": "50000000"}),
                200,
            )
            confirmed = track(published, "CREATE_PLAN", mh, plan_draft_id=draft["id"])
            assert (
                track(published, "CREATE_PLAN", mh, plan_draft_id=draft["id"])
                == confirmed
            )
            assert check(client.get(API + "/plans/1"), 200)["title"] == "Real contract"
            send(token.functions.approve(contract.address, 200_000_000), customer)
            subscribed = send(contract.functions.subscribe(1), customer)
            track(subscribed, "SUBSCRIBE", ch, plan_id="1")
            recovered = send(contract.functions.subscribe(1), customer)
            assert run_scan(app.state.engine, vault, settings, max_batches=10)[1]
            memberships = check(client.get(API + "/me/subscriptions", headers=ch), 200)[
                "items"
            ]
            assert {item["subscription_id"] for item in memberships} == {"1", "2"}
            events = check(
                client.get(API + "/subscriptions/2/events", headers=ch), 200
            )["items"]
            assert events[0]["tx_hash"] == recovered
            if adapter:
                for fn in [
                    token.functions.mint(funder, 122),
                    token.functions.approve(adapter.address, 122),
                    adapter.functions.fundYield(1, 101),
                    adapter.functions.fundYield(2, 21),
                ]:
                    assert (
                        w3.eth.wait_for_transaction_receipt(
                            fn.transact({"from": funder})
                        ).status
                        == 1
                    )
            advance(61)
            assert check(
                client.get(API + "/subscriptions/1/eligibility", headers=ch), 200
            )["can_check_in"]
            message = {
                "subscriptionId": 1,
                "merchant": merchant.address,
                "periodIndex": 1,
                "nonce": 0,
                "deadline": w3.eth.get_block("latest").timestamp + 120,
            }
            types = json.loads(
                (ROOT / "shared/check-in.types.json").read_text(encoding="utf-8")
            )
            domain = {
                "name": "PrepaidGuard",
                "version": "1",
                "chainId": 31337,
                "verifyingContract": contract.address,
            }
            signature = customer.sign_message(
                encode_typed_data(domain, types, message)
            ).signature
            release = contract.functions.checkInWithSignature(
                tuple(message.values()), signature
            )
            released = send(release, merchant)
            track(released, "CHECK_IN", mh, subscription_id="1")
            track(
                send(release, merchant, expected=0),
                "CHECK_IN",
                mh,
                expected="REVERTED",
                subscription_id="1",
            )
            first = check(client.get(API + "/subscriptions/1", headers=ch), 200)
            assert (
                first["remaining_principal"]
                == first["principal_released"]
                == "50000000"
            )
            if adapter:
                assert first["yield_summary"]["paid_merchant"] == "70"
                assert first["yield_summary"]["paid_subscriber"] == "20"
                assert first["yield_summary"]["paid_platform"] == "11"
            advance(121)
            assert check(
                client.get(API + "/subscriptions/2/eligibility", headers=ch), 200
            )["can_refund"]
            refunded = send(contract.functions.refund(2), customer)
            track(refunded, "REFUND", ch, subscription_id="2")
            second = check(client.get(API + "/subscriptions/2", headers=ch), 200)
            assert (
                second["status"] == "REFUNDED"
                and second["principal_refunded"] == "100000000"
            )
            assert token.functions.balanceOf(merchant.address).call() == 50_000_000 + (
                84 if adapter else 0
            )
            assert token.functions.balanceOf(customer.address).call() == 100_000_000 + (
                24 if adapter else 0
            )
            assert contract.functions.totalPrincipal().call() == 50_000_000
            custody = adapter.address if adapter else contract.address
            assert token.functions.balanceOf(custody).call() == 50_000_000
    finally:
        with admin.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin.dispose()
