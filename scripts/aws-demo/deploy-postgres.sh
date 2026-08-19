#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
AWS_DEMO_HOST_OVERRIDE="${AWS_DEMO_HOST-}"

if [ -f "$ROOT_DIR/scripts/env/aws-demo.env" ]; then
  . "$ROOT_DIR/scripts/env/aws-demo.env"
elif [ -f "$ROOT_DIR/scripts/env/aws-demo.local.env" ]; then
  . "$ROOT_DIR/scripts/env/aws-demo.local.env"
fi

if [ -n "$AWS_DEMO_HOST_OVERRIDE" ]; then
  AWS_DEMO_HOST="$AWS_DEMO_HOST_OVERRIDE"
fi

TARGET_ENV="${TARGET_ENV:-aws-demo}"
TARGET_HOST="${AWS_DEMO_HOST:-aws-demo}"

SERVICE_NAME="fastapi-is-cool"
POSTGRES_IMAGE="postgres:16"
POSTGRES_CONTAINER="${SERVICE_NAME}-postgres"
DOCKER_NETWORK="${SERVICE_NAME}-net"

REMOTE_ROOT="/srv/${SERVICE_NAME}"
REMOTE_POSTGRES_DATA_DIR="${REMOTE_ROOT}/postgres/data"
REMOTE_ENV_DIR="${REMOTE_ROOT}/env"
REMOTE_POSTGRES_ENV_FILE="${REMOTE_ENV_DIR}/postgres.env"

ssh "$TARGET_HOST" "sudo sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
SERVICE_NAME="$SERVICE_NAME"
POSTGRES_IMAGE="$POSTGRES_IMAGE"
POSTGRES_CONTAINER="$POSTGRES_CONTAINER"
DOCKER_NETWORK="$DOCKER_NETWORK"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_POSTGRES_DATA_DIR="$REMOTE_POSTGRES_DATA_DIR"
REMOTE_ENV_DIR="$REMOTE_ENV_DIR"
REMOTE_POSTGRES_ENV_FILE="$REMOTE_POSTGRES_ENV_FILE"

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

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required on \$TARGET_ENV."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: docker is not available through sudo on \$TARGET_ENV."
  exit 1
fi

mkdir -p "\$REMOTE_POSTGRES_DATA_DIR"
mkdir -p "\$REMOTE_ENV_DIR"
chmod 700 "\$REMOTE_ENV_DIR"

if [ ! -f "\$REMOTE_POSTGRES_ENV_FILE" ]; then
  cat >&2 <<ENVMSG
Missing required PostgreSQL env file:
  \$REMOTE_POSTGRES_ENV_FILE

Create it manually on aws-demo before running this script.

Expected contents:
  POSTGRES_DB=fastapi_is_cool
  POSTGRES_USER=fastapi_is_cool
  POSTGRES_PASSWORD=<strong-production-like-password>

The file should be owned by root and readable only by root:
  sudo chmod 600 \$REMOTE_POSTGRES_ENV_FILE
ENVMSG
  exit 1
fi

chmod 600 "\$REMOTE_POSTGRES_ENV_FILE"
echo "Found aws-demo PostgreSQL env file."

if ! docker network inspect "\$DOCKER_NETWORK" >/dev/null 2>&1; then
  docker network create "\$DOCKER_NETWORK"
  echo "Created Docker network: \$DOCKER_NETWORK"
else
  echo "Found Docker network: \$DOCKER_NETWORK"
fi

docker pull "\$POSTGRES_IMAGE"

if docker inspect "\$POSTGRES_CONTAINER" >/dev/null 2>&1; then
  if [ "\$(docker inspect -f '{{.State.Running}}' "\$POSTGRES_CONTAINER")" = "true" ]; then
    echo "PostgreSQL container is already running: \$POSTGRES_CONTAINER"
  else
    docker start "\$POSTGRES_CONTAINER"
    echo "Started existing PostgreSQL container: \$POSTGRES_CONTAINER"
  fi
else
  docker run -d \\
    --name "\$POSTGRES_CONTAINER" \\
    --restart unless-stopped \\
    --network "\$DOCKER_NETWORK" \\
    --env-file "\$REMOTE_POSTGRES_ENV_FILE" \\
    -v "\$REMOTE_POSTGRES_DATA_DIR:/var/lib/postgresql/data" \\
    "\$POSTGRES_IMAGE"

  echo "Created PostgreSQL container: \$POSTGRES_CONTAINER"
fi

echo "Waiting for PostgreSQL readiness..."
for _ in \$(seq 1 30); do
  if docker exec "\$POSTGRES_CONTAINER" pg_isready \\
    -U fastapi_is_cool \\
    -d fastapi_is_cool >/dev/null 2>&1; then
    echo "PostgreSQL is ready."
    echo "Docker network endpoint: \$POSTGRES_CONTAINER:5432"
    echo "No host port is published for aws-demo PostgreSQL."
    exit 0
  fi

  sleep 1
done

echo "PostgreSQL did not become ready in time."
exit 1
EOF

echo
echo "Next step:"
echo "  scripts/aws-demo/alembic.sh upgrade"
