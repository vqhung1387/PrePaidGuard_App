from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.core.config import Settings


def make_engine(settings: Settings) -> Engine:
    url = settings.database_url.get_secret_value()
    if url.startswith(("postgres://", "postgresql://")):
        url = "postgresql+psycopg://" + url.split("://", 1)[1]
    options = make_url(url).query.get("options", "")
    return create_engine(
        url,
        pool_pre_ping=True,
        hide_parameters=True,
        connect_args={"connect_timeout": 5, "options": f"{options} -c timezone=UTC"},
    )


def get_db(request: Request) -> Iterator[Session]:
    with Session(request.app.state.engine, expire_on_commit=False) as db:
        yield db


def lock(db: Session, key: str) -> None:
    db.execute(
        text("select pg_advisory_xact_lock(hashtextextended(:key, 0))"), {"key": key}
    )
