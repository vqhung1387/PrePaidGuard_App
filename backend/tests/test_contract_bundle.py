import json
from pathlib import Path

from eth_account import Account
from eth_account.messages import encode_typed_data
from web3 import Web3

from app.blockchain.vault import Vault
from app.core.config import Settings

SHARED = Path(__file__).resolve().parents[2] / "shared"


def test_exported_abi_is_compatible_with_backend(tmp_path):
    manifest = tmp_path / "deployment.json"
    manifest.write_text(
        json.dumps(
            {
                "deployment_id": "abi-validation-only",
                "chain_id": 43113,
                "chain_name": "Fuji",
                "public_rpc_url": "https://api.avax-test.network/ext/bc/C/rpc",
                "explorer_url": "https://testnet.snowtrace.io",
                "vault_address": "0x4444444444444444444444444444444444444444",
                "token": {"address": "0x5555555555555555555555555555555555555555"},
                "abi_version": "prepaidguard-1",
                "deployment_block": 0,
                "yield_mode": "MOCK",
                "subscription_status_codes": {
                    "active": 1,
                    "completed": 2,
                    "refunded": 3,
                },
            }
        ),
        encoding="utf-8",
    )
    vault = Vault(
        Settings(
            _env_file=None,
            abi_file=SHARED / "abi/PrepaidVault.json",
            deployment_file=manifest,
        )
    )
    assert vault.contract.get_function_by_name("checkInWithSignature")


def test_typescript_signing_vector_matches_python():
    fixture = json.loads((SHARED / "check-in.fixture.json").read_text(encoding="utf-8"))
    signed = encode_typed_data(fixture["domain"], fixture["types"], fixture["message"])
    assert Web3.to_hex(signed.header) == fixture["domainSeparator"]
    assert Web3.to_hex(signed.body) == fixture["structHash"]
    digest = Web3.keccak(b"\x19" + signed.version + signed.header + signed.body)
    assert Web3.to_hex(digest) == fixture["digest"]
    assert (
        Account.recover_message(signed, signature=fixture["signature"])
        == fixture["signer"]
    )
