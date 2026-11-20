"""Public club boards and consent-based member connections."""

import secrets
from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
from typing import Literal
from uuid import UUID, uuid4

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlalchemy import text

from app.api.dependencies import Current, CurrentMerchant, Db
from app.core.errors import ApiError

router = APIRouter(tags=["club community"])
VN = timezone(timedelta(hours=7))


class Entry(BaseModel):
    branch: str = Field(min_length=1, max_length=100)
    kind: Literal["attendance", "class", "trainer", "notice"]
    title: str = Field(default="", max_length=120)
    detail: str = Field(default="", max_length=500)
    day: date
    minute: int = Field(default=0, ge=0, lt=1440)
    amount: int = Field(default=0, ge=0, le=100000)


@router.get("/clubs")
def clubs(db: Db):
    rows = db.execute(
        text("""SELECT DISTINCT m.id AS merchant_id, m.business_name, COALESCE(e.branch,m.business_name) AS branch
        FROM merchants m LEFT JOIN club_entries e ON e.merchant_id=m.id ORDER BY m.business_name,branch,m.id""")
    )
    return list(rows.mappings())


@router.get("/clubs/{merchant}/board")
def board(merchant: UUID, branch: str, day: date, db: Db):
    rows = db.execute(
        text("""SELECT id,kind,title,detail,day,minute,amount,created FROM club_entries
        WHERE merchant_id=:merchant AND branch=:branch AND
        ((kind IN ('attendance','class') AND day=:day) OR kind='trainer')
        ORDER BY minute,title,id"""),
        {"merchant": merchant, "branch": branch, "day": day},
    )
    return list(rows.mappings())


@router.get("/club-notices")
def notices(db: Db):
    return list(
        db.execute(
            text("""SELECT id,branch,title,detail,created FROM club_entries
        WHERE kind='notice' ORDER BY created DESC,id DESC LIMIT 100""")
        ).mappings()
    )


@router.post("/merchant/club-entries", status_code=201)
def publish(body: Entry, db: Db, merchant: CurrentMerchant):
    now = datetime.now(VN)
    data = body.model_dump()
    for field in ("branch", "title", "detail"):
        data[field] = data[field].strip()
    if not data["branch"] or (body.kind != "attendance" and not data["title"]):
        raise ApiError(422, "EMPTY_FIELD", "Hãy nhập tên chi nhánh và nội dung.")
    if body.kind == "class" and not 1 <= body.amount <= 1440:
        raise ApiError(422, "DURATION", "Thời lượng lớp phải từ 1 đến 1440 phút.")
    conflict = ""
    if body.kind == "attendance":
        if (body.day, body.minute // 60) > (now.date(), now.hour):
            raise ApiError(422, "FUTURE_HOUR", "Chưa thể ghi nhận giờ trong tương lai.")
        data["minute"] = body.minute // 60 * 60
        conflict = """ ON CONFLICT (merchant_id,branch,day,minute) WHERE kind='attendance'
                       DO UPDATE SET amount=excluded.amount,created=excluded.created"""
    data.update(id=uuid4(), merchant=merchant.id, created=now)
    row = db.execute(
        text(
            """INSERT INTO club_entries (id,merchant_id,branch,kind,title,detail,day,minute,amount,created)
        VALUES (:id,:merchant,:branch,:kind,:title,:detail,:day,:minute,:amount,:created)"""
            + conflict
            + " RETURNING id"
        ),
        data,
    )
    result = row.scalar_one()
    db.commit()
    return {"id": result}


class Invite(BaseModel):
    code: str = Field(min_length=24, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")


@router.post("/me/buddy-invites")
def invite(db: Db, principal: Current):
    code = secrets.token_urlsafe(24)
    db.execute(
        text(
            "INSERT INTO buddy_invites(digest,owner,expires) VALUES(:key,:uid,:expires)"
        ),
        {
            "key": sha256(code.encode()).hexdigest(),
            "uid": principal.user.id,
            "expires": datetime.now(VN) + timedelta(days=7),
        },
    )
    db.commit()
    return {"code": code}


@router.post("/me/buddies")
def accept(body: Invite, db: Db, principal: Current):
    key = sha256(body.code.encode()).hexdigest()
    owner = db.scalar(
        text(
            "SELECT owner FROM buddy_invites WHERE digest=:key AND expires>now() FOR UPDATE"
        ),
        {"key": key},
    )
    if owner is None or owner == principal.user.id:
        raise ApiError(
            422, "INVITE_INVALID", "Mã của chính bạn, đã dùng hoặc đã hết hạn."
        )
    first, second = sorted([owner, principal.user.id])
    db.execute(
        text("INSERT INTO buddy_pairs VALUES (:a,:b) ON CONFLICT DO NOTHING"),
        {"a": first, "b": second},
    )
    db.execute(text("DELETE FROM buddy_invites WHERE digest=:key"), {"key": key})
    db.commit()
    return {"connected": True}


@router.get("/me/buddies")
def buddies(db: Db, principal: Current):
    return list(
        db.execute(
            text("""SELECT u.id,u.display_name FROM buddy_pairs p
        JOIN users u ON u.id=CASE WHEN first_id=:uid THEN second_id ELSE first_id END
        WHERE first_id=:uid OR second_id=:uid ORDER BY u.display_name,u.id"""),
            {"uid": principal.user.id},
        ).mappings()
    )
