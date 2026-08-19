#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
AWS_DEMO_HOST_OVERRIDE="${AWS_DEMO_HOST-}"
BUILD_ARTIFACT_DIR_WSL_OVERRIDE="${BUILD_ARTIFACT_DIR_WSL-}"

if [ -f "$ROOT_DIR/scripts/env/aws-demo.env" ]; then
  . "$ROOT_DIR/scripts/env/aws-demo.env"
elif [ -f "$ROOT_DIR/scripts/env/aws-demo.local.env" ]; then
  . "$ROOT_DIR/scripts/env/aws-demo.local.env"
fi

if [ -n "$AWS_DEMO_HOST_OVERRIDE" ]; then
  AWS_DEMO_HOST="$AWS_DEMO_HOST_OVERRIDE"
fi

if [ -n "$BUILD_ARTIFACT_DIR_WSL_OVERRIDE" ]; then
  BUILD_ARTIFACT_DIR_WSL="$BUILD_ARTIFACT_DIR_WSL_OVERRIDE"
fi

usage() {
  echo "Usage: IMAGE_TAR=/path/to/image.tar $0 <upgrade|current|history|downgrade>"
  echo
  echo "Runs Alembic in a one-off Docker container on aws-demo."
}

TARGET_ENV="${TARGET_ENV:-aws-demo}"
TARGET_HOST="${AWS_DEMO_HOST:-aws-demo}"
SERVICE_NAME="${SERVICE_NAME:-fastapi-is-cool}"
DOCKER_NETWORK="${SERVICE_NAME}-net"
REMOTE_ROOT="/srv/${SERVICE_NAME}"
REMOTE_ENV_DIR="${REMOTE_ROOT}/env"
REMOTE_APP_ENV_FILE="${REMOTE_ENV_DIR}/app.env"
REMOTE_IMAGE_DIR="${REMOTE_ROOT}/images"
BUILD_ARTIFACT_DIR_WSL="${BUILD_ARTIFACT_DIR_WSL:-/mnt/j/deploy_remote_repo/artifacts}"

command="${1:-}"
case "$command" in
  upgrade|current|history|downgrade)
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [ "$command" = "upgrade" ]; then
  alembic_args="upgrade head"
elif [ "$command" = "downgrade" ]; then
  alembic_args="downgrade -1"
else
  alembic_args="$command"
fi

if [ "${IMAGE_TAR:-}" ]; then
  LOCAL_IMAGE_TAR="$IMAGE_TAR"
else
  LOCAL_IMAGE_TAR="$(ls -t "$BUILD_ARTIFACT_DIR_WSL"/"$SERVICE_NAME"-*.tar 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$LOCAL_IMAGE_TAR" ] || [ ! -f "$LOCAL_IMAGE_TAR" ]; then
  echo "Error: image tarball not found."
  echo "Build one first with scripts/build/build-image-tar.sh, or pass IMAGE_TAR=/path/to/image.tar."
  exit 1
fi

REMOTE_TMP_TAR="/tmp/$(basename "$LOCAL_IMAGE_TAR")"
REMOTE_IMAGE_TAR="${REMOTE_IMAGE_DIR}/$(basename "$LOCAL_IMAGE_TAR")"

echo "Preparing image on aws-demo for Alembic:"
echo "  host: $TARGET_HOST"
echo "  local tar: $LOCAL_IMAGE_TAR"
echo "  command: alembic $alembic_args"

scp "$LOCAL_IMAGE_TAR" "$TARGET_HOST:$REMOTE_TMP_TAR"

ssh "$TARGET_HOST" "sudo sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
SERVICE_NAME="$SERVICE_NAME"
DOCKER_NETWORK="$DOCKER_NETWORK"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_ENV_DIR="$REMOTE_ENV_DIR"
REMOTE_APP_ENV_FILE="$REMOTE_APP_ENV_FILE"
REMOTE_IMAGE_DIR="$REMOTE_IMAGE_DIR"
REMOTE_TMP_TAR="$REMOTE_TMP_TAR"
REMOTE_IMAGE_TAR="$REMOTE_IMAGE_TAR"
ALEMBIC_ARGS="$alembic_args"

if [ "\$TARGET_ENV" != "aws-demo" ]; then
  echo "Refusing to run: TARGET_ENV must be aws-demo."
  exit 1
fi

case "\$REMOTE_ROOT" in
  /srv/*-dev|*/dev*|*dev-demo*)
    echo "Refusing to run: aws-demo must not use dev paths."
    exit 1
    ;;
  /srv/*)
    ;;
  *)
    echo "Refusing to run: REMOTE_ROOT must be a dedicated /srv path."
    exit 1
    ;;
esac

if [ ! -f "\$REMOTE_APP_ENV_FILE" ]; then
  echo "Error: missing app env file: \$REMOTE_APP_ENV_FILE"
  echo "Run scripts/aws-demo/setup-env.sh and create the required env file first."
  exit 1
fi

if ! docker network inspect "\$DOCKER_NETWORK" >/dev/null 2>&1; then
  echo "Error: missing Docker network: \$DOCKER_NETWORK"
  echo "Run scripts/aws-demo/deploy-postgres.sh first."
  exit 1
fi

mkdir -p "\$REMOTE_IMAGE_DIR"
mv "\$REMOTE_TMP_TAR" "\$REMOTE_IMAGE_TAR"
chmod 600 "\$REMOTE_IMAGE_TAR"

LOAD_OUTPUT="\$(docker load --input "\$REMOTE_IMAGE_TAR")"
echo "\$LOAD_OUTPUT"
IMAGE_REF="\$(printf '%s\n' "\$LOAD_OUTPUT" | sed -n 's/^Loaded image: //p' | tail -n 1)"

if [ -z "\$IMAGE_REF" ]; then
  echo "Error: could not determine loaded image reference."
  exit 1
fi

docker run --rm \\
  --network "\$DOCKER_NETWORK" \\
  --env-file "\$REMOTE_APP_ENV_FILE" \\
  "\$IMAGE_REF" \\
  uv run alembic \$ALEMBIC_ARGS
EOF

if [ "$command" = "upgrade" ]; then
  echo
  echo "Next step:"
  echo "  IMAGE_TAR=\"$LOCAL_IMAGE_TAR\" scripts/aws-demo/seed-content-snippets.sh"
fi
