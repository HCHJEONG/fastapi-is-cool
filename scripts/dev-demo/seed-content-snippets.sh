#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TARGET_HOST="yoga"
DEV_DEMO_LAN_IP="192.168.0.104"
SERVICE_NAME="fastapi-is-cool"
REMOTE_ROOT="/srv/${SERVICE_NAME}-dev"
REMOTE_POSTGRES_ENV_FILE="${REMOTE_ROOT}/env/postgres.env"

cd "$ROOT_DIR"

POSTGRES_PASSWORD="$(
  ssh "$TARGET_HOST" "sed -n 's/^POSTGRES_PASSWORD=//p' '$REMOTE_POSTGRES_ENV_FILE' | head -n 1" || true
)"

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Error: could not read POSTGRES_PASSWORD from dev-demo."
  echo "Run scripts/dev-demo/setup-env.sh first."
  exit 1
fi

DATABASE_URL="postgresql+asyncpg://fastapi_is_cool:${POSTGRES_PASSWORD}@${DEV_DEMO_LAN_IP}:5432/fastapi_is_cool"
export DATABASE_URL

uv run python -m app.seeds.content_snippets
