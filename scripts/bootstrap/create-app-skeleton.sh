#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

usage() {
  echo "Usage: $0"
  echo
  echo "Creates the baseline FastAPI app skeleton without overwriting existing files."
  echo "The baseline includes PostgreSQL, SQLAlchemy async, Alembic, and seed code."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac

  shift
done

create_dir() {
  mkdir -p "$ROOT_DIR/$1"
  echo "Ensured directory: $1"
}

create_file_once() {
  path="$ROOT_DIR/$1"

  if [ -f "$path" ]; then
    echo "Found existing file: $1"
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  cat > "$path"
  echo "Created file: $1"
}

cd "$ROOT_DIR"

create_dir "app"
create_dir "app/api"
create_dir "app/api/v1"
create_dir "app/core"
create_dir "tests"
create_dir "alembic"
create_dir "alembic/versions"
create_dir "app/db"
create_dir "app/models"
create_dir "app/schemas"
create_dir "app/seeds"
create_dir "app/services"

create_file_once "app/__init__.py" <<'EOF'
EOF

create_file_once "app/main.py" <<'EOF'
from fastapi import FastAPI

from app.api.health import router as health_router
from app.api.router import api_router


def create_app() -> FastAPI:
    app = FastAPI(title="fastapi-is-cool")
    app.include_router(health_router)
    app.include_router(api_router)
    return app


app = create_app()
EOF

create_file_once "app/api/__init__.py" <<'EOF'
EOF

create_file_once "app/api/router.py" <<'EOF'
from fastapi import APIRouter

from app.api.v1.router import api_v1_router

api_router = APIRouter()
api_router.include_router(api_v1_router, prefix="/api/v1")
EOF

create_file_once "app/api/health.py" <<'EOF'
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
EOF

create_file_once "app/api/v1/__init__.py" <<'EOF'
EOF

create_file_once "app/api/v1/router.py" <<'EOF'
from fastapi import APIRouter

from app.api.v1 import snippets

api_v1_router = APIRouter()
api_v1_router.include_router(snippets.router, prefix="/snippets", tags=["snippets"])
EOF

create_file_once "app/api/v1/snippets.py" <<'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db_session
from app.schemas.snippets import ContentSnippetRead
from app.services.snippets import get_content_snippet_by_key

router = APIRouter()


@router.get("/{key}", response_model=ContentSnippetRead)
async def get_snippet(
    key: str,
    session: AsyncSession = Depends(get_db_session),
) -> ContentSnippetRead:
    snippet = await get_content_snippet_by_key(session, key)
    if snippet is None:
        raise HTTPException(status_code=404, detail="Snippet not found.")

    return ContentSnippetRead.model_validate(snippet)
EOF

create_file_once "app/core/__init__.py" <<'EOF'
EOF

create_file_once "app/core/config.py" <<'EOF'
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "local"
    log_level: str = "info"
    database_url: str | None = None

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
EOF

create_file_once "alembic.ini" <<'EOF'
[alembic]
script_location = alembic
prepend_sys_path = .
path_separator = os

sqlalchemy.url = postgresql+asyncpg://fastapi_is_cool:password@localhost:5432/fastapi_is_cool

[post_write_hooks]

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARNING
handlers = console
qualname =

[logger_sqlalchemy]
level = WARNING
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
EOF

create_file_once "alembic/env.py" <<'EOF'
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from app import models  # noqa: F401
from app.core.config import get_settings
from app.db.base import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

settings = get_settings()
if settings.database_url is None:
    raise RuntimeError("DATABASE_URL is required to run Alembic migrations.")

config.set_main_option("sqlalchemy.url", settings.database_url)
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    import asyncio

    asyncio.run(run_migrations_online())
EOF

create_file_once "alembic/versions/0001_create_content_snippets.py" <<'EOF'
"""create content snippets

Revision ID: 0001
Revises:
Create Date: 2026-08-19
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "content_snippets",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("key", sa.String(length=128), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_content_snippets_key",
        "content_snippets",
        ["key"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_content_snippets_key", table_name="content_snippets")
    op.drop_table("content_snippets")
EOF

create_file_once "app/db/__init__.py" <<'EOF'
EOF

create_file_once "app/db/base.py" <<'EOF'
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
EOF

create_file_once "app/db/session.py" <<'EOF'
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

settings = get_settings()

if settings.database_url is None:
    engine = None
    async_session_factory = None
else:
    engine = create_async_engine(settings.database_url, pool_pre_ping=True)
    async_session_factory = async_sessionmaker(engine, expire_on_commit=False)


async def get_db_session() -> AsyncIterator[AsyncSession]:
    if async_session_factory is None:
        raise RuntimeError("DATABASE_URL is not configured.")

    async with async_session_factory() as session:
        yield session
EOF

create_file_once "app/models/__init__.py" <<'EOF'
from app.models.content_snippet import ContentSnippet

__all__ = ["ContentSnippet"]
EOF

create_file_once "app/models/content_snippet.py" <<'EOF'
from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ContentSnippet(Base):
    __tablename__ = "content_snippets"

    id: Mapped[int] = mapped_column(primary_key=True)
    key: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(255))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
EOF

create_file_once "app/schemas/__init__.py" <<'EOF'
EOF

create_file_once "app/schemas/snippets.py" <<'EOF'
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ContentSnippetRead(BaseModel):
    key: str
    title: str
    body: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
EOF

create_file_once "app/seeds/__init__.py" <<'EOF'
EOF

create_file_once "app/seeds/content_snippets.py" <<'EOF'
import asyncio

from sqlalchemy.dialects.postgresql import insert

from app.db.session import async_session_factory
from app.models.content_snippet import ContentSnippet

SEED_SNIPPETS = [
    {
        "key": "home.hero",
        "title": "Home Hero",
        "body": "FastAPI is cool.",
    },
]


async def main() -> None:
    if async_session_factory is None:
        raise RuntimeError("DATABASE_URL is not configured.")

    async with async_session_factory() as session:
        for item in SEED_SNIPPETS:
            stmt = (
                insert(ContentSnippet)
                .values(**item)
                .on_conflict_do_update(
                    index_elements=[ContentSnippet.key],
                    set_={
                        "title": item["title"],
                        "body": item["body"],
                    },
                )
            )
            await session.execute(stmt)

        await session.commit()


if __name__ == "__main__":
    asyncio.run(main())
EOF

create_file_once "app/services/__init__.py" <<'EOF'
EOF

create_file_once "app/services/snippets.py" <<'EOF'
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_snippet import ContentSnippet


async def get_content_snippet_by_key(
    session: AsyncSession,
    key: str,
) -> ContentSnippet | None:
    result = await session.execute(
        select(ContentSnippet).where(ContentSnippet.key == key)
    )
    return result.scalar_one_or_none()
EOF

create_file_once "tests/test_health.py" <<'EOF'
from httpx import ASGITransport, AsyncClient

from app.main import app


async def test_health() -> None:
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
EOF

echo "App skeleton creation completed."
