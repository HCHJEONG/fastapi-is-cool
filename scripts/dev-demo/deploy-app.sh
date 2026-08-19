#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEV_DEMO_HOST_OVERRIDE="${DEV_DEMO_HOST-}"
DEV_DEMO_LAN_IP_OVERRIDE="${DEV_DEMO_LAN_IP-}"
DEV_DEMO_APP_PORT_OVERRIDE="${DEV_DEMO_APP_PORT-}"
BUILD_ARTIFACT_DIR_WSL_OVERRIDE="${BUILD_ARTIFACT_DIR_WSL-}"

if [ -f "$ROOT_DIR/scripts/env/dev-demo.env" ]; then
  . "$ROOT_DIR/scripts/env/dev-demo.env"
elif [ -f "$ROOT_DIR/scripts/env/dev-demo.local.env" ]; then
  . "$ROOT_DIR/scripts/env/dev-demo.local.env"
fi

if [ -n "$DEV_DEMO_HOST_OVERRIDE" ]; then
  DEV_DEMO_HOST="$DEV_DEMO_HOST_OVERRIDE"
fi

if [ -n "$DEV_DEMO_LAN_IP_OVERRIDE" ]; then
  DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP_OVERRIDE"
fi

if [ -n "$DEV_DEMO_APP_PORT_OVERRIDE" ]; then
  DEV_DEMO_APP_PORT="$DEV_DEMO_APP_PORT_OVERRIDE"
fi

if [ -n "$BUILD_ARTIFACT_DIR_WSL_OVERRIDE" ]; then
  BUILD_ARTIFACT_DIR_WSL="$BUILD_ARTIFACT_DIR_WSL_OVERRIDE"
fi

TARGET_ENV="${TARGET_ENV:-dev-demo}"
TARGET_HOST="${DEV_DEMO_HOST:-yoga}"
DEV_DEMO_LAN_IP="${DEV_DEMO_LAN_IP:-192.168.0.104}"
DEV_DEMO_APP_PORT="${DEV_DEMO_APP_PORT:-8000}"
SERVICE_NAME="${SERVICE_NAME:-fastapi-is-cool}"
APP_CONTAINER="${SERVICE_NAME}-app-dev"
DOCKER_NETWORK="${SERVICE_NAME}-dev-net"
REMOTE_ROOT="/srv/${SERVICE_NAME}-dev"
REMOTE_ENV_DIR="${REMOTE_ROOT}/env"
REMOTE_APP_ENV_FILE="${REMOTE_ENV_DIR}/app.env"
REMOTE_IMAGE_DIR="${REMOTE_ROOT}/images"
BUILD_ARTIFACT_DIR_WSL="${BUILD_ARTIFACT_DIR_WSL:-/mnt/j/deploy_remote_repo/artifacts}"

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

REMOTE_IMAGE_TAR="${REMOTE_IMAGE_DIR}/$(basename "$LOCAL_IMAGE_TAR")"

echo "Deploying app image to dev-demo:"
echo "  host: $TARGET_HOST"
echo "  local tar: $LOCAL_IMAGE_TAR"
echo "  remote tar: $REMOTE_IMAGE_TAR"
echo "  app port: $DEV_DEMO_LAN_IP:$DEV_DEMO_APP_PORT"

ssh "$TARGET_HOST" "sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP"
DEV_DEMO_APP_PORT="$DEV_DEMO_APP_PORT"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_ENV_DIR="$REMOTE_ENV_DIR"
REMOTE_APP_ENV_FILE="$REMOTE_APP_ENV_FILE"
REMOTE_IMAGE_DIR="$REMOTE_IMAGE_DIR"

if [ "\$TARGET_ENV" != "dev-demo" ]; then
  echo "Refusing to run: TARGET_ENV must be dev-demo."
  exit 1
fi

case "\$REMOTE_ROOT" in
  /srv/*-dev)
    ;;
  *)
    echo "Refusing to run: REMOTE_ROOT must be a dev-specific /srv path."
    exit 1
    ;;
esac

if ! hostname -I | tr ' ' '\n' | grep -qx "\$DEV_DEMO_LAN_IP"; then
  echo "Refusing to run: \$DEV_DEMO_LAN_IP is not assigned to this host."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required on dev-demo."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: docker is not available to the current SSH user."
  exit 1
fi

if [ ! -f "\$REMOTE_APP_ENV_FILE" ]; then
  echo "Error: missing app env file: \$REMOTE_APP_ENV_FILE"
  echo "Run scripts/dev-demo/setup-env.sh first."
  exit 1
fi

mkdir -p "\$REMOTE_IMAGE_DIR"
EOF

scp "$LOCAL_IMAGE_TAR" "$TARGET_HOST:$REMOTE_IMAGE_TAR"

ssh "$TARGET_HOST" "sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP"
DEV_DEMO_APP_PORT="$DEV_DEMO_APP_PORT"
SERVICE_NAME="$SERVICE_NAME"
APP_CONTAINER="$APP_CONTAINER"
DOCKER_NETWORK="$DOCKER_NETWORK"
REMOTE_APP_ENV_FILE="$REMOTE_APP_ENV_FILE"
REMOTE_IMAGE_TAR="$REMOTE_IMAGE_TAR"

if [ "\$TARGET_ENV" != "dev-demo" ]; then
  echo "Refusing to run: TARGET_ENV must be dev-demo."
  exit 1
fi

if ! docker network inspect "\$DOCKER_NETWORK" >/dev/null 2>&1; then
  docker network create "\$DOCKER_NETWORK"
  echo "Created Docker network: \$DOCKER_NETWORK"
else
  echo "Found Docker network: \$DOCKER_NETWORK"
fi

LOAD_OUTPUT="\$(docker load --input "\$REMOTE_IMAGE_TAR")"
echo "\$LOAD_OUTPUT"
IMAGE_REF="\$(printf '%s\n' "\$LOAD_OUTPUT" | sed -n 's/^Loaded image: //p' | tail -n 1)"

if [ -z "\$IMAGE_REF" ]; then
  echo "Error: could not determine loaded image reference."
  exit 1
fi

if docker inspect "\$APP_CONTAINER" >/dev/null 2>&1; then
  if [ "\$(docker inspect -f '{{.State.Running}}' "\$APP_CONTAINER")" = "true" ]; then
    docker stop "\$APP_CONTAINER"
  fi

  docker rm "\$APP_CONTAINER"
fi

docker run -d \\
  --name "\$APP_CONTAINER" \\
  --restart unless-stopped \\
  --network "\$DOCKER_NETWORK" \\
  --env-file "\$REMOTE_APP_ENV_FILE" \\
  -p "\$DEV_DEMO_LAN_IP:\$DEV_DEMO_APP_PORT:8000" \\
  "\$IMAGE_REF"

echo "Waiting for app health..."
for _ in \$(seq 1 30); do
  if docker exec "\$APP_CONTAINER" python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=2).read()' >/dev/null 2>&1; then
    echo "App health check passed."
    echo
    echo "Deployment completed."
    echo
    echo "Verify from your local machine:"
    echo "  curl http://\$DEV_DEMO_LAN_IP:\$DEV_DEMO_APP_PORT/health"
    echo "  curl http://\$DEV_DEMO_LAN_IP:\$DEV_DEMO_APP_PORT/api/v1/snippets/home.hero"
    exit 0
  fi

  sleep 1
done

echo "App did not become healthy in time."
docker logs --tail 100 "\$APP_CONTAINER" || true
exit 1
EOF

echo
echo "After dev-demo verification succeeds, continue with:"
echo "  scripts/aws-demo/setup-env.sh"
