from datetime import UTC, datetime
from typing import Annotated

from pydantic import AfterValidator, BeforeValidator, Field, StringConstraints

UINT_MAX = 2**256 - 1
# Largest Unix second representable by Python/API datetime (9999-12-31T23:59:59Z).
MAX_TIMESTAMP = 253402300799


def timestamp_supported(value: int) -> bool:
    return type(value) is int and 0 <= value <= MAX_TIMESTAMP


def bounded_uint(value: str) -> str:
    number = int(value)
    if number > UINT_MAX:
        raise ValueError("must fit uint256")
    return str(number)


Address = Annotated[
    str, StringConstraints(pattern=r"^0x[0-9a-fA-F]{40}$", to_lower=True)
]
Hash32 = Annotated[
    str, StringConstraints(pattern=r"^0x[0-9a-fA-F]{64}$", to_lower=True)
]
Signature = Annotated[str, StringConstraints(pattern=r"^0x[0-9a-fA-F]{130}$")]
UintString = Annotated[
    str, StringConstraints(pattern=r"^[0-9]{1,78}$"), AfterValidator(bounded_uint)
]
ChainId = Annotated[int, Field(gt=0, le=2**63 - 1)]


def uint_output(value: int | str) -> str:
    return str(value)


UintOut = Annotated[UintString, BeforeValidator(uint_output)]


def utcnow() -> datetime:
    return datetime.now(UTC)
