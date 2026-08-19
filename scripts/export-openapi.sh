#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OPENAPI_URL="${OPENAPI_URL:-http://127.0.0.1:8000/openapi.json}"
OUTPUT_PATH="${OUTPUT_PATH:-$ROOT_DIR/scripts/openapi/openapi.json}"

usage() {
  echo "Usage: $0"
  echo
  echo "Exports the running FastAPI OpenAPI schema to scripts/openapi/openapi.json."
  echo
  echo "Environment variables:"
  echo "  OPENAPI_URL   Source schema URL. Default: http://127.0.0.1:8000/openapi.json"
  echo "  OUTPUT_PATH   Destination file. Default: scripts/openapi/openapi.json"
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

mkdir -p "$(dirname "$OUTPUT_PATH")"
curl --fail --silent --show-error "$OPENAPI_URL" -o "$OUTPUT_PATH"
echo "Exported OpenAPI schema to $OUTPUT_PATH"
