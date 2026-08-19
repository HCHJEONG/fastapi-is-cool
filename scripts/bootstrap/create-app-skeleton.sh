#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

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
create_dir "app/db"
create_dir "app/models"
create_dir "app/schemas"
create_dir "app/services"
create_dir "tests"

create_file_once "app/__init__.py" <<'EOF'
EOF

create_file_once "app/main.py" <<'EOF'
from fastapi import FastAPI

from app.api.router import api_router


def create_app() -> FastAPI:
    app = FastAPI(title="fastapi-is-cool")
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

create_file_once "app/api/v1/__init__.py" <<'EOF'
EOF

create_file_once "app/api/v1/router.py" <<'EOF'
from fastapi import APIRouter

from app.api.v1 import health, snippets

api_v1_router = APIRouter()
api_v1_router.include_router(health.router)
api_v1_router.include_router(snippets.router, prefix="/snippets", tags=["snippets"])
EOF

create_file_once "app/api/v1/health.py" <<'EOF'
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
EOF

create_file_once "app/api/v1/snippets.py" <<'EOF'
from fastapi import APIRouter, HTTPException

router = APIRouter()


@router.get("/{key}")
async def get_snippet(key: str) -> dict[str, str]:
    raise HTTPException(
        status_code=501,
        detail="Snippet lookup is not implemented yet.",
    )
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
        response = await client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
EOF

echo "App skeleton creation completed."
