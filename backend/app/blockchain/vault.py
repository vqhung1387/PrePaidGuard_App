import json
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from eth_abi.exceptions import DecodingError
from eth_utils import event_abi_to_log_topic, function_signature_to_4byte_selector
from pydantic import ValidationError
from requests.exceptions import RequestException
from web3 import Web3
from web3.exceptions import (
    ContractLogicError,
    TransactionNotFound,
    Web3Exception,
)

from app.core.config import Deployment, Settings, backend_path
from app.core.errors import config_error, not_found, rpc_error

ZERO = "0x" + "0" * 40
EVENTS = {
    "PlanCreated": (
        "PLAN_CREATED",
        (
            "planId",
            "merchant",
            "clientReference",
            "token",
            "pricePerPeriod",
            "totalPeriods",
            "periodDuration",
            "gracePeriod",
        ),
    ),
    "Subscribed": (
        "SUBSCRIBED",
        (
            "subscriptionId",
            "planId",
            "subscriber",
            "principal",
            "startedAt",
            "nextReleaseAt",
        ),
    ),
    "PeriodReleased": (
        "PERIOD_RELEASED",
        (
            "subscriptionId",
            "planId",
            "periodIndex",
            "principal",
            "merchantYield",
            "subscriberYield",
            "platformYield",
            "nonceAfter",
            "nextReleaseAt",
            "completed",
        ),
    ),
    "Refunded": (
        "REFUNDED",
        (
            "subscriptionId",
            "planId",
            "principal",
            "merchantYield",
            "subscriberYield",
            "platformYield",
            "nonceAfter",
        ),
    ),
}
ACTION = {
    "CREATE_PLAN": ("createPlan", "PLAN_CREATED"),
    "SUBSCRIBE": ("subscribe", "SUBSCRIBED"),
    "CHECK_IN": ("checkInWithSignature", "PERIOD_RELEASED"),
    "REFUND": ("refund", "REFUNDED"),
}
PLAN_FIELDS = (
    "planId",
    "clientReference",
    "merchant",
    "token",
    "pricePerPeriod",
    "totalPeriods",
    "periodDuration",
    "gracePeriod",
)
SUBSCRIPTION_FIELDS = (
    "subscriptionId",
    "planId",
    "subscriber",
    "initialPrincipal",
    "remainingPrincipal",
    "completedPeriods",
    "nonce",
    "startedAt",
    "nextReleaseAt",
    "status",
)
CHECK_IN_FIELDS = (
    ("subscriptionId", "uint256"),
    ("merchant", "address"),
    ("periodIndex", "uint256"),
    ("nonce", "uint256"),
    ("deadline", "uint256"),
)
FIELD_TYPES = {
    "merchant": "address",
    "subscriber": "address",
    "token": "address",
    "clientReference": "bytes32",
    "completed": "bool",
}


def named_fields(abi_fields: list[dict], fields: tuple[str, ...]) -> bool:
    types = {item["name"]: item["type"] for item in abi_fields}
    return len(abi_fields) == len(fields) and all(
        name in types
        and (
            types[name] == FIELD_TYPES[name]
            if name in FIELD_TYPES
            else types[name].startswith("uint") and types[name][4:].isdigit()
        )
        for name in fields
    )


def struct_outputs(abi: dict) -> list[dict]:
    outputs = abi["outputs"]
    if len(outputs) == 1 and outputs[0]["type"] == "tuple":
        return outputs[0]["components"]
    return outputs


def hex_value(value) -> str:
    return value.lower() if isinstance(value, str) else Web3.to_hex(value)


def chain_time(seconds: int) -> datetime:
    try:
        return datetime.fromtimestamp(seconds, UTC)
    except (ValueError, OverflowError, OSError):
        raise config_error() from None


@dataclass(frozen=True)
class Block:
    number: int
    hash: str
    timestamp: datetime


@dataclass(frozen=True)
class Log:
    name: str
    args: dict[str, Any]
    tx_hash: str
    index: int
    block_number: int
    block_hash: str

    @property
    def payload(self) -> dict:
        return {
            name: hex_value(value)
            if isinstance(value, (bytes, str))
            else str(value)
            if type(value) is int
            else value
            for name, value in self.args.items()
            if name not in {"planId", "subscriptionId"}
        }


class Vault:
    def __init__(self, settings: Settings):
        if not settings.deployment_file or not settings.abi_file:
            raise config_error()
        try:
            deployment = Deployment.model_validate_json(
                backend_path(settings.deployment_file).read_text(encoding="utf-8")
            )
            abi = json.loads(
                backend_path(settings.abi_file).read_text(encoding="utf-8")
            )
            if isinstance(abi, dict):
                abi = abi["abi"]
            if deployment.chain_id != settings.chain_id:
                raise config_error()
            if settings.environment == "demo" and (
                not deployment.public_rpc_url.startswith("https://")
                or not deployment.explorer_url.startswith("https://")
            ):
                raise config_error()
            rpc_url = (
                settings.rpc_url.get_secret_value()
                if settings.rpc_url
                else deployment.public_rpc_url
            )
            self.web3 = Web3(
                Web3.HTTPProvider(
                    rpc_url,
                    exception_retry_configuration=None,
                    request_kwargs={
                        "timeout": settings.rpc_timeout_seconds,
                    },
                )
            )
            self.deployment = deployment
            self.status_codes = {
                code: name.upper()
                for name, code in deployment.subscription_status_codes.model_dump().items()
            }
            self.address = Web3.to_checksum_address(deployment.vault_address)
            self.contract = self.web3.eth.contract(address=self.address, abi=abi)
            self._validate_functions()
            self.events = {}
            for name, (kind, fields) in EVENTS.items():
                event = self.contract.get_event_by_name(name)
                if event.abi["anonymous"] or not named_fields(
                    event.abi["inputs"], fields
                ):
                    raise config_error()
                self.events[hex_value(event_abi_to_log_topic(event.abi))] = kind, event
        except (
            OSError,
            ValueError,
            TypeError,
            KeyError,
            ValidationError,
            Web3Exception,
        ):
            raise config_error() from None

    def _validate_functions(self) -> None:
        def abi(name: str) -> dict:
            return self.contract.get_function_by_name(name).abi

        for name, id_name in (("subscribe", "planId"), ("refund", "subscriptionId")):
            inputs = abi(name)["inputs"]
            if [(field["name"], field["type"]) for field in inputs] != [
                (id_name, "uint256")
            ]:
                raise config_error()
        if not named_fields(
            abi("createPlan")["inputs"],
            (
                "clientReference",
                "token",
                "pricePerPeriod",
                "totalPeriods",
                "periodDuration",
                "gracePeriod",
            ),
        ):
            raise config_error()
        check_in = abi("checkInWithSignature")["inputs"]
        if [field["type"] for field in check_in] != ["tuple", "bytes"] or tuple(
            (field["name"], field["type"]) for field in check_in[0]["components"]
        ) != CHECK_IN_FIELDS:
            raise config_error()
        for name, fields in (
            ("getPlan", PLAN_FIELDS),
            ("getSubscription", SUBSCRIPTION_FIELDS),
        ):
            getter = abi(name)
            if [field["type"] for field in getter["inputs"]] != ["uint256"]:
                raise config_error()
            outputs = struct_outputs(getter)
            expected = (
                fields
                if any(field["name"] == fields[0] for field in outputs)
                else fields[1:]
            )
            relevant = [field for field in outputs if field["name"] in expected]
            if not named_fields(relevant, expected):
                raise config_error()
        if self.deployment.yield_mode == "MOCK":
            estimate = abi("estimateYield")
            if [field["type"] for field in estimate["inputs"]] != ["uint256"] or [
                field["type"] for field in estimate["outputs"]
            ] != ["uint256"]:
                raise config_error()

    @property
    def scope(self) -> dict:
        return {
            "chain_id": self.deployment.chain_id,
            "vault_address": self.deployment.vault_address,
        }

    @property
    def lock_key(self) -> str:
        return f"vault:{self.deployment.chain_id}:{self.deployment.vault_address}"

    def explorer(self, tx_hash: str) -> str:
        return f"{self.deployment.explorer_url.rstrip('/')}/tx/{tx_hash}"

    def checked_head(self) -> Block:
        try:
            if self.web3.eth.chain_id != self.deployment.chain_id:
                raise config_error()
            block = self.block("latest")
            if block.number < self.deployment.deployment_block:
                raise config_error()
            return block
        except (Web3Exception, RequestException, OSError, ValueError):
            raise rpc_error() from None

    def check_contract(self, block: Block) -> None:
        try:
            token_address = Web3.to_checksum_address(self.deployment.token.address)
            if not self.web3.eth.get_code(self.address, block.number):
                raise config_error()
            if not self.web3.eth.get_code(token_address, block.number):
                raise config_error()
            raw = self.web3.eth.call(
                {"to": token_address, "data": "0x313ce567"}, block.number
            )
            if (
                self.web3.codec.decode(["uint8"], raw)[0]
                != self.deployment.token.decimals
            ):
                raise config_error()
            self.require_canonical(block)
        except (ContractLogicError, DecodingError):
            raise config_error() from None
        except (Web3Exception, RequestException, OSError, ValueError):
            raise rpc_error() from None

    def block(self, number: int | str) -> Block:
        try:
            block = self.web3.eth.get_block(number)
            return Block(
                block["number"],
                hex_value(block["hash"]),
                chain_time(block["timestamp"]),
            )
        except (Web3Exception, RequestException, OSError, ValueError, KeyError):
            raise rpc_error() from None

    def require_canonical(self, block: Block) -> None:
        if self.block(block.number).hash != block.hash:
            raise rpc_error()

    def _read_struct(
        self, name: str, id_: int, block: Block, fields: tuple, absent: str
    ) -> dict:
        try:
            fn = self.contract.get_function_by_name(name)(id_)
            result = fn.call(block_identifier=block.number)
            outputs = struct_outputs(fn.abi)
            values = dict(zip((item["name"] for item in outputs), result, strict=True))
            # Some Solidity getters omit the ID because it is already an input.
            values.setdefault(fields[0], id_)
            if values[fields[0]] != id_ or not set(fields) <= values.keys():
                raise config_error()
            return values
        except ContractLogicError as exc:
            selector = "0x" + function_signature_to_4byte_selector(f"{absent}()").hex()
            if isinstance(exc.data, str) and exc.data.lower() == selector:
                raise not_found() from None
            raise rpc_error() from None
        except (Web3Exception, RequestException, OSError):
            raise rpc_error() from None
        except (TypeError, ValueError, KeyError):
            raise config_error() from None

    def plan(self, id_: int, block: Block) -> dict:
        plan = self._read_struct("getPlan", id_, block, PLAN_FIELDS, "InvalidPlan")
        if plan["merchant"].lower() == ZERO:
            raise not_found()
        if plan["token"].lower() != self.deployment.token.address:
            raise config_error()
        return plan

    def subscription(self, id_: int, block: Block) -> dict:
        sub = self._read_struct(
            "getSubscription", id_, block, SUBSCRIPTION_FIELDS, "InvalidSubscription"
        )
        if sub["subscriber"].lower() == ZERO:
            raise not_found()
        try:
            sub["status"] = self.status_codes[sub["status"]]
        except KeyError:
            raise config_error() from None
        return sub

    def estimate(self, subscription_id: int, block: Block) -> int:
        try:
            return self.contract.functions.estimateYield(subscription_id).call(
                block_identifier=block.number
            )
        except (Web3Exception, RequestException, OSError, ValueError):
            raise rpc_error() from None

    def tx_receipt(self, tx_hash: str) -> tuple[Any | None, Any | None]:
        try:
            try:
                tx = self.web3.eth.get_transaction(tx_hash)
            except TransactionNotFound:
                return None, None
            try:
                receipt = self.web3.eth.get_transaction_receipt(tx_hash)
            except TransactionNotFound:
                receipt = None
            return tx, receipt
        except (Web3Exception, RequestException, OSError, ValueError):
            raise rpc_error() from None

    def calldata(self, data) -> tuple[str, dict]:
        fn, args = self.contract.decode_function_input(data)
        return fn.fn_name, args

    def decode_log(self, raw) -> Log | None:
        if raw["address"].lower() != self.deployment.vault_address or not raw["topics"]:
            return None
        known = self.events.get(hex_value(raw["topics"][0]))
        if known is None:
            return None
        if raw.get("removed"):
            raise rpc_error()
        kind, event = known
        try:
            decoded = event.process_log(raw)
            return Log(
                kind,
                dict(decoded["args"]),
                hex_value(decoded["transactionHash"]),
                decoded["logIndex"],
                decoded["blockNumber"],
                hex_value(decoded["blockHash"]),
            )
        except (Web3Exception, DecodingError, ValueError, TypeError, KeyError):
            raise rpc_error() from None

    def logs(self, first: int, last: int) -> list[Log]:
        try:
            raw_logs = self.web3.eth.get_logs(
                {
                    "address": self.address,
                    "fromBlock": first,
                    "toBlock": last,
                    "topics": [list(self.events)],
                }
            )
        except (Web3Exception, RequestException, OSError, ValueError):
            raise rpc_error() from None
        logs = [
            entry for raw in raw_logs if (entry := self.decode_log(raw)) is not None
        ]
        if any(not first <= entry.block_number <= last for entry in logs):
            raise rpc_error()
        return sorted(logs, key=lambda entry: (entry.block_number, entry.index))
