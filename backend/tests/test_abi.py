import json
from copy import deepcopy

import pytest

from app.blockchain.vault import Vault
from app.core.config import Settings
from app.core.errors import ApiError
from tests.fake_rpc import ABI, TOKEN, VAULT


def vault_settings(tmp_path, abi):
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "deployment_id": "abi-check",
                "chain_id": 43113,
                "chain_name": "Fuji",
                "public_rpc_url": "https://public.example.test",
                "explorer_url": "https://explorer.example.test",
                "vault_address": VAULT,
                "token": {"address": TOKEN},
                "abi_version": "1",
                "deployment_block": 100,
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
    artifact = tmp_path / "abi.json"
    artifact.write_text(json.dumps({"abi": abi}), encoding="utf-8")
    return Settings(abi_file=artifact, deployment_file=manifest)


def test_abi_accepts_named_flat_getters(tmp_path):
    abi = deepcopy(ABI)
    for entry in abi:
        if entry["name"] in {"getPlan", "getSubscription"}:
            entry["outputs"] = entry["outputs"][0]["components"]
    vault = Vault(vault_settings(tmp_path, abi))
    assert vault.deployment.chain_id == 43113


@pytest.mark.parametrize(
    "change",
    [
        "check_in_order",
        "check_in_type",
        "getter_field",
        "event_type",
        "missing_estimate",
    ],
)
def test_abi_fails_before_rpc_when_interface_is_incompatible(tmp_path, change):
    abi = deepcopy(ABI)
    entries = {entry["name"]: entry for entry in abi}
    if change in {"check_in_order", "check_in_type"}:
        check_in = entries["checkInWithSignature"]["inputs"][0]["components"]
        if change == "check_in_order":
            check_in[2], check_in[3] = check_in[3], check_in[2]
        else:
            check_in[2]["type"] = "uint32"
    elif change == "getter_field":
        entries["getSubscription"]["outputs"][0]["components"].pop()
    elif change == "event_type":
        entries["PeriodReleased"]["inputs"][-1]["type"] = "uint8"
    else:
        abi.remove(entries["estimateYield"])

    with pytest.raises(ApiError) as error:
        Vault(vault_settings(tmp_path, abi))
    assert error.value.code == "CONFIG_MISMATCH"
