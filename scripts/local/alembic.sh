#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

usage() {
  echo "Usage: $0 <upgrade|current|history|downgrade|revision> [message]"
  echo
  echo "Examples:"
  echo "  $0 upgrade"
  echo "  $0 current"
  echo "  $0 revision \"add source app to snippets\""
}

cd "$ROOT_DIR"

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
