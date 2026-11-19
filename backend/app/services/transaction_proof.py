"""Recover a nonce from signed bytes without storing or broadcasting them."""

from eth_account import Account
from eth_account._utils.legacy_transactions import Transaction
from eth_account._utils.signing import extract_chain_id
from eth_account.typed_transactions import TypedTransaction
from eth_keys.exceptions import BadSignature
from eth_utils.exceptions import ValidationError
from hexbytes import HexBytes
from rlp.exceptions import RLPException
from web3 import Web3

from app.core.errors import ApiError
from app.schemas.types import UINT_MAX


def original_nonce(raw: str, tx_hash: str, wallet: str, chain_id: int) -> int:
    try:
        encoded = HexBytes(raw)
        if Web3.to_hex(Web3.keccak(encoded)) != tx_hash:
            raise ValueError("hash mismatch")
        if Account.recover_transaction(encoded).lower() != wallet:
            raise ValueError("signer mismatch")
        if encoded[0] <= 0x7F:
            decoded = TypedTransaction.from_bytes(encoded).as_dict()
            signed_chain = decoded["chainId"]
        else:
            decoded = Transaction.from_bytes(encoded).as_dict()
            signed_chain, _ = extract_chain_id(decoded["v"])
        nonce = decoded["nonce"]
        if (
            signed_chain != chain_id
            or type(nonce) is not int
            or not 0 <= nonce <= UINT_MAX
        ):
            raise ValueError("chain or nonce mismatch")
        return nonce
    except (
        ValueError,
        TypeError,
        IndexError,
        KeyError,
        RLPException,
        BadSignature,
        ValidationError,
    ):
        raise ApiError(
            409,
            "INVALID_ORIGINAL_TRANSACTION",
            "Giao dịch đã ký không khớp hash, ví hoặc chain gốc.",
        ) from None
