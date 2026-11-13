from base64 import b64decode, urlsafe_b64encode
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import Query
from sqlalchemy import tuple_
from sqlalchemy.orm import Session

from app.core.errors import ApiError

Limit = Annotated[int, Query(ge=1, le=100)]
Cursor = Annotated[str | None, Query(max_length=160)]


def paginate(
    db: Session, query, columns: tuple, types: tuple, limit: int, cursor: str | None
):
    if cursor is not None:
        try:
            values = (
                b64decode(cursor, altchars=b"-_", validate=True).decode().split("|")
            )
            key = tuple(
                datetime.fromisoformat(value) if convert is datetime else convert(value)
                for convert, value in zip(types, values, strict=True)
            )
            if any(
                (isinstance(value, datetime) and value.utcoffset() is None)
                or (isinstance(value, int) and not 0 <= value < 2**256)
                for value in key
            ):
                raise ValueError
        except (ValueError, TypeError, UnicodeError):
            raise ApiError(422, "VALIDATION_ERROR", "Cursor không hợp lệ.") from None
        query = query.where(tuple_(*columns) < key)
    rows = list(
        db.scalars(
            query.order_by(*(column.desc() for column in columns)).limit(limit + 1)
        )
    )
    next_cursor = None
    if len(rows) > limit:
        rows.pop()
        key = "|".join(str(getattr(rows[-1], column.key)) for column in columns)
        next_cursor = urlsafe_b64encode(key.encode()).decode()
    return rows, next_cursor


TIMESTAMP_KEY = datetime, UUID
