import secrets
from uuid import UUID

from fastapi import APIRouter
from pydantic import ValidationError
from sqlalchemy import select

from app.api.dependencies import Current, CurrentMerchant, Db
from app.api.system import Chain
from app.core.db import lock
from app.core.errors import ApiError, not_found
from app.models.entities import Merchant, PlanDraft, User
from app.schemas.api import (
    DraftResponse,
    DraftUpdate,
    MerchantCreate,
    MerchantResponse,
    MerchantUpdate,
    Page,
    PlanTerms,
)
from app.services.pagination import TIMESTAMP_KEY, Cursor, Limit, paginate

router = APIRouter(tags=["merchant and plan metadata"])


def merchant_response(merchant: Merchant, owner_wallet: str) -> MerchantResponse:
    return MerchantResponse(
        id=merchant.id,
        owner_wallet=owner_wallet,
        business_name=merchant.business_name,
        description=merchant.description,
        location_text=merchant.location_text,
        created_at=merchant.created_at,
        updated_at=merchant.updated_at,
    )


@router.post("/merchants", status_code=201, response_model=MerchantResponse)
def create_merchant(body: MerchantCreate, db: Db, principal: Current):
    lock(db, f"merchant:{principal.user.id}")
    if db.scalar(
        select(Merchant.id).where(Merchant.owner_user_id == principal.user.id)
    ):
        raise ApiError(409, "MERCHANT_EXISTS", "Ví này đã có hồ sơ cơ sở.")
    merchant = Merchant(owner_user_id=principal.user.id, **body.model_dump())
    db.add(merchant)
    db.commit()
    return merchant_response(merchant, principal.user.wallet_address)


@router.get("/merchants/{merchant_id}", response_model=MerchantResponse)
def get_merchant(merchant_id: UUID, db: Db):
    row = db.execute(
        select(Merchant, User.wallet_address)
        .join(User, User.id == Merchant.owner_user_id)
        .where(Merchant.id == merchant_id)
    ).one_or_none()
    if row is None:
        raise not_found()
    return merchant_response(*row)


@router.patch("/merchants/{merchant_id}", response_model=MerchantResponse)
def update_merchant(
    merchant_id: UUID, body: MerchantUpdate, db: Db, principal: Current
):
    merchant = db.scalar(
        select(Merchant).where(
            Merchant.id == merchant_id, Merchant.owner_user_id == principal.user.id
        )
    )
    if merchant is None:
        raise not_found()
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(merchant, field, value)
    db.commit()
    return merchant_response(merchant, principal.user.wallet_address)


@router.post("/plan-drafts", status_code=201, response_model=DraftResponse)
def create_draft(body: PlanTerms, db: Db, merchant: CurrentMerchant, vault: Chain):
    draft = PlanDraft(
        **body.model_dump(exclude={"price_per_period"}),
        price_per_period=int(body.price_per_period),
        merchant_id=merchant.id,
        client_reference="0x" + secrets.token_hex(32),
        token_address=vault.deployment.token.address,
        **vault.scope,
    )
    db.add(draft)
    db.commit()
    return draft


@router.get("/plan-drafts", response_model=Page[DraftResponse])
def list_drafts(
    db: Db,
    merchant: CurrentMerchant,
    vault: Chain,
    limit: Limit = 20,
    cursor: Cursor = None,
):
    rows, next_cursor = paginate(
        db,
        select(PlanDraft).filter_by(merchant_id=merchant.id, **vault.scope),
        (PlanDraft.created_at, PlanDraft.id),
        TIMESTAMP_KEY,
        limit,
        cursor,
    )
    return {"items": rows, "next_cursor": next_cursor}


def own_draft(
    db: Db, draft_id: UUID, owner_id: UUID, vault: Chain, *, for_update=False
):
    query = (
        select(PlanDraft)
        .join(Merchant)
        .where(
            PlanDraft.id == draft_id,
            Merchant.owner_user_id == owner_id,
            PlanDraft.chain_id == vault.deployment.chain_id,
            PlanDraft.vault_address == vault.deployment.vault_address,
        )
    )
    draft = db.scalar(query.with_for_update(of=PlanDraft) if for_update else query)
    if draft is None:
        raise not_found()
    return draft


@router.get("/plan-drafts/{draft_id}", response_model=DraftResponse)
def get_draft(draft_id: UUID, db: Db, principal: Current, vault: Chain):
    return own_draft(db, draft_id, principal.user.id, vault)


@router.patch("/plan-drafts/{draft_id}", response_model=DraftResponse)
def update_draft(
    draft_id: UUID, body: DraftUpdate, db: Db, principal: Current, vault: Chain
):
    draft = own_draft(db, draft_id, principal.user.id, vault, for_update=True)
    if draft.state != "DRAFT":
        raise ApiError(409, "PLAN_IMMUTABLE", "Gói đã công bố, không thể sửa.")
    values = {key: getattr(draft, key) for key in PlanTerms.model_fields}
    values["price_per_period"] = str(draft.price_per_period)
    values.update(body.model_dump(exclude_unset=True))
    try:
        terms = PlanTerms.model_validate(values)
    except ValidationError:
        raise ApiError(
            422, "VALIDATION_ERROR", "Điều khoản gói không hợp lệ."
        ) from None
    for field, value in terms.model_dump().items():
        setattr(draft, field, int(value) if field == "price_per_period" else value)
    db.commit()
    return draft
