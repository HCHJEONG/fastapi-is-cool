#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEV_DEMO_HOST_OVERRIDE="${DEV_DEMO_HOST-}"
DEV_DEMO_LAN_IP_OVERRIDE="${DEV_DEMO_LAN_IP-}"

if [ -f "$ROOT_DIR/scripts/env/dev-demo.local.env" ]; then
  . "$ROOT_DIR/scripts/env/dev-demo.local.env"
fi

if [ -n "$DEV_DEMO_HOST_OVERRIDE" ]; then
  DEV_DEMO_HOST="$DEV_DEMO_HOST_OVERRIDE"
fi

if [ -n "$DEV_DEMO_LAN_IP_OVERRIDE" ]; then
  DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP_OVERRIDE"
fi

TARGET_HOST="${DEV_DEMO_HOST:-yoga}"
DEV_DEMO_LAN_IP="${DEV_DEMO_LAN_IP:-192.168.0.104}"
SERVICE_NAME="fastapi-is-cool"
REMOTE_ROOT="/srv/${SERVICE_NAME}-dev"
REMOTE_POSTGRES_ENV_FILE="${REMOTE_ROOT}/env/postgres.env"

usage() {
  echo "Usage: $0 <upgrade|current|history|downgrade|revision> [message]"
  echo
  echo "Examples:"
  echo "  $0 upgrade"
  echo "  $0 current"
  echo "  $0 revision \"add source app to snippets\""
  echo
  echo "Runs Alembic from this checkout against the dev-demo PostgreSQL endpoint."
}

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

command="${1:-}"
case "$command" in
  upgrade)
    uv run alembic upgrade head
    ;;
  current)
    uv run alembic current
    ;;
  history)
    uv run alembic history
    ;;
  downgrade)
    uv run alembic downgrade -1
    ;;
  revision)
    message="${2:-}"
    if [ -z "$message" ]; then
      usage
      exit 2
    fi
    uv run alembic revision --autogenerate -m "$message"
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
