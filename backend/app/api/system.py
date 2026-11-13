from typing import Annotated

from fastapi import APIRouter, Depends, Request
from sqlalchemy import text

from app.api.dependencies import Config, Db
from app.blockchain.vault import Vault
from app.core.errors import database_error
from app.schemas.api import ConfigResponse, Health

router = APIRouter(tags=["system"])


def get_vault(request: Request) -> Vault:
    vault = request.app.state.vault
    if vault is None:
        vault = Vault(request.app.state.settings)
        request.app.state.vault = vault
    return vault


Chain = Annotated[Vault, Depends(get_vault)]


@router.get("/health", response_model=Health)
def health():
    return {"status": "ok"}


@router.get("/ready", response_model=Health)
def ready(db: Db, request: Request):
    if not db.execute(
        text("select version_num from alembic_version")
    ).scalar_one_or_none():
        raise database_error()
    vault = get_vault(request)
    vault.check_contract(vault.checked_head())
    return {"status": "ready"}


@router.get("/api/v1/config", response_model=ConfigResponse)
def config(settings: Config, vault: Chain):
    deployment = vault.deployment
    return ConfigResponse(
        environment=settings.environment,
        deployment_id=deployment.deployment_id,
        chain_id=deployment.chain_id,
        chain_name=deployment.chain_name,
        rpc_url=deployment.public_rpc_url,
        explorer_url=deployment.explorer_url,
        vault_address=deployment.vault_address,
        token=deployment.token,
        abi_version=deployment.abi_version,
        yield_mode=deployment.yield_mode,
        auth_domain=settings.auth_domain,
        auth_uri=settings.auth_uri,
    )
