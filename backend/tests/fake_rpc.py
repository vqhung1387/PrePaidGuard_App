from eth_utils import event_abi_to_log_topic
from requests.exceptions import ConnectionError
from web3 import Web3

VAULT = "0x" + "44" * 20
TOKEN = "0x" + "33" * 20
BASE_TIME = 1_795_000_000


def fields(spec):
    return [{"name": name, "type": type_} for name, type_ in spec]


def function(name, inputs, outputs=()):
    return {
        "type": "function",
        "name": name,
        "inputs": list(inputs),
        "outputs": list(outputs),
        "stateMutability": "view" if outputs else "nonpayable",
    }


def event(name, spec, indexed):
    return {
        "type": "event",
        "name": name,
        "anonymous": False,
        "inputs": [
            dict(item, indexed=item["name"] in indexed) for item in fields(spec)
        ],
    }


def tuple_field(name, spec):
    return {"name": name, "type": "tuple", "components": fields(spec)}


PLAN = (
    ("planId", "uint256"),
    ("clientReference", "bytes32"),
    ("merchant", "address"),
    ("token", "address"),
    ("pricePerPeriod", "uint256"),
    ("totalPeriods", "uint32"),
    ("periodDuration", "uint64"),
    ("gracePeriod", "uint64"),
)
SUB = (
    ("subscriptionId", "uint256"),
    ("planId", "uint256"),
    ("subscriber", "address"),
    ("initialPrincipal", "uint256"),
    ("remainingPrincipal", "uint256"),
    ("completedPeriods", "uint32"),
    ("nonce", "uint256"),
    ("startedAt", "uint64"),
    ("nextReleaseAt", "uint64"),
    ("status", "uint8"),
)
CHECK_IN = (
    ("subscriptionId", "uint256"),
    ("merchant", "address"),
    ("periodIndex", "uint256"),
    ("nonce", "uint256"),
    ("deadline", "uint256"),
)
PAYOUT = (
    ("subscriptionId", "uint256"),
    ("planId", "uint256"),
    ("principal", "uint256"),
    ("merchantYield", "uint256"),
    ("subscriberYield", "uint256"),
    ("platformYield", "uint256"),
    ("nonceAfter", "uint256"),
)
ABI = [
    function("createPlan", fields((PLAN[1], *PLAN[3:]))),
    function("subscribe", fields((PLAN[0],))),
    function(
        "checkInWithSignature",
        [tuple_field("message", CHECK_IN), *fields((("signature", "bytes"),))],
    ),
    function("refund", fields((SUB[0],))),
    function("getPlan", fields((PLAN[0],)), [tuple_field("plan", PLAN[1:])]),
    function(
        "getSubscription", fields((SUB[0],)), [tuple_field("subscription", SUB[1:])]
    ),
    function("estimateYield", fields((SUB[0],)), fields((("amount", "uint256"),))),
    event(
        "PlanCreated",
        (PLAN[0], PLAN[2], PLAN[1], *PLAN[3:]),
        {"planId", "merchant", "clientReference"},
    ),
    event(
        "Subscribed",
        (*SUB[:3], ("principal", "uint256"), SUB[7], SUB[8]),
        {"planId", "subscriptionId"},
    ),
    event(
        "PeriodReleased",
        (
            *PAYOUT[:2],
            ("periodIndex", "uint256"),
            *PAYOUT[2:],
            SUB[8],
            ("completed", "bool"),
        ),
        {"subscriptionId"},
    ),
    event("Refunded", PAYOUT, {"subscriptionId"}),
]


class FakeRpc:
    def __init__(self, vault):
        self.vault = vault
        self.codec = Web3().codec
        self.chain_id = 43113
        self.head = 101
        self.outage = False
        self.timestamps = {}
        self.hashes = {}
        self.logs = []
        self.transactions = {}
        self.receipts = {}
        self.plans = {}
        self.subs = {}
        self.estimated = 17

    def block_hash(self, n):
        return self.hashes.get(n, f"0x{n:064x}")

    def timestamp(self, n):
        return self.timestamps.get(n, BASE_TIME + n)

    def request(self, method, params):
        if self.outage:
            raise ConnectionError("private URL must not appear in errors")
        if method == "eth_chainId":
            result = hex(self.chain_id)
        elif method == "eth_getBlockByNumber":
            n = self.head if params[0] == "latest" else int(params[0], 16)
            result = {
                "number": hex(n),
                "hash": self.block_hash(n),
                "timestamp": hex(self.timestamp(n)),
            }
        elif method == "eth_getCode":
            result = "0x6001"
        elif method == "eth_getTransactionByHash":
            result = self.transactions.get(params[0])
        elif method == "eth_getTransactionReceipt":
            result = self.receipts.get(params[0])
        elif method == "eth_getLogs":
            filter_ = params[0]
            first, last = int(filter_["fromBlock"], 16), int(filter_["toBlock"], 16)
            result = [
                log for log in self.logs if first <= int(log["blockNumber"], 16) <= last
            ]
        elif method == "eth_call":
            data = params[0]["data"]
            if data == "0x313ce567":
                result = Web3.to_hex(self.codec.encode(["uint8"], [6]))
            else:
                name, args = self.vault.calldata(data)
                if name == "estimateYield":
                    result = Web3.to_hex(
                        self.codec.encode(["uint256"], [self.estimated])
                    )
                else:
                    spec, rows = (
                        (PLAN, self.plans) if name == "getPlan" else (SUB, self.subs)
                    )
                    values = rows.get(next(iter(args.values())))
                    if values is None:
                        values = {
                            field: "0x" + "00" * 20
                            if type_ == "address"
                            else b"\0" * 32
                            if type_ == "bytes32"
                            else 0
                            for field, type_ in spec
                        }
                    result = Web3.to_hex(
                        self.codec.encode(
                            ["(" + ",".join(type_ for _, type_ in spec[1:]) + ")"],
                            [tuple(values[field] for field, _ in spec[1:])],
                        )
                    )
        else:
            raise AssertionError(f"Unexpected RPC method {method}")
        return {"jsonrpc": "2.0", "id": 1, "result": result}

    def add_tx(
        self,
        num,
        block,
        sender,
        fn,
        args,
        *,
        event_name=None,
        event_args=None,
        status=1,
        to=VAULT,
        emitter=VAULT,
        add_to_index=True,
    ):
        tx_hash = f"0x{10_000 + num:064x}"
        self.transactions[tx_hash] = {
            "hash": tx_hash,
            "blockHash": self.block_hash(block),
            "blockNumber": hex(block),
            "chainId": hex(self.chain_id),
            "from": sender,
            "to": to,
            "input": self.vault.contract.encode_abi(fn, args=args),
        }
        logs = []
        if event_name:
            event_abi = next(
                item
                for item in ABI
                if item["type"] == "event" and item["name"] == event_name
            )
            data = [item for item in event_abi["inputs"] if not item["indexed"]]
            log = {
                "address": emitter,
                "topics": [
                    Web3.to_hex(event_abi_to_log_topic(event_abi)),
                    *[
                        Web3.to_hex(
                            self.codec.encode(
                                [item["type"]], [event_args[item["name"]]]
                            )
                        )
                        for item in event_abi["inputs"]
                        if item["indexed"]
                    ],
                ],
                "data": Web3.to_hex(
                    self.codec.encode(
                        [item["type"] for item in data],
                        [event_args[item["name"]] for item in data],
                    )
                ),
                "blockNumber": hex(block),
                "blockHash": self.block_hash(block),
                "transactionHash": tx_hash,
                "transactionIndex": "0x0",
                "logIndex": "0x0",
                "removed": False,
            }
            logs.append(log)
            if add_to_index:
                self.logs.append(log)
        self.receipts[tx_hash] = {
            "transactionHash": tx_hash,
            "blockHash": self.block_hash(block),
            "blockNumber": hex(block),
            "from": sender,
            "to": to,
            "status": hex(status),
            "logs": logs,
        }
        return tx_hash
