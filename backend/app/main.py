import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.exc import DBAPIError
from starlette.concurrency import run_in_threadpool

from app.api import auth, metadata, reads, system, transactions
from app.blockchain.vault import Vault
from app.core.config import Settings
from app.core.db import make_engine
from app.core.errors import ERROR_RESPONSES, ApiError, register_errors
from app.services.sync import run_scan

logger = logging.getLogger("uvicorn.error")


def create_app(settings: Settings | None = None, vault: Vault | None = None) -> FastAPI:
    settings = settings if settings is not None else Settings()
    engine = make_engine(settings)

    def scan(app: FastAPI) -> None:
        if app.state.vault is None:
            app.state.vault = Vault(settings)
        run_scan(engine, app.state.vault, settings, max_batches=2)

    async def scan_periodically(app: FastAPI, stop: asyncio.Event) -> None:
        while not stop.is_set():
            try:
                await run_in_threadpool(scan, app)
            except ApiError as exc:
                logger.warning("Vault sync delayed (%s)", exc.code)
            except DBAPIError:
                logger.warning("Vault sync delayed (DATABASE_UNAVAILABLE)")
            try:
                await asyncio.wait_for(stop.wait(), settings.sync_interval_seconds)
            except TimeoutError:
                pass

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        stop = asyncio.Event()
        worker = (
            asyncio.create_task(scan_periodically(app, stop))
            if settings.sync_interval_seconds
            else None
        )
        try:
            yield
        finally:
            stop.set()
            try:
                if worker is not None:
                    await worker
            finally:
                engine.dispose()

    app = FastAPI(
        title="PrePaidGuard API",
        version="0.1.0",
        lifespan=lifespan,
        responses=ERROR_RESPONSES,
    )
    app.state.settings = settings
    app.state.engine = engine
    app.state.vault = vault
    register_errors(app)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PATCH"],
            allow_headers=["Authorization", "Content-Type"],
            expose_headers=["X-Request-ID", "Retry-After", "WWW-Authenticate"],
        )
    app.include_router(system.router)
    for router in (auth.router, metadata.router, reads.router, transactions.router):
        app.include_router(router, prefix="/api/v1")
    return app


app = create_app()
