#!/usr/bin/env sh
set -eu

TARGET_ENV="dev-demo"
TARGET_HOST="yoga"
DEV_DEMO_LAN_IP="192.168.0.104"

SERVICE_NAME="fastapi-is-cool"
POSTGRES_IMAGE="postgres:16"
POSTGRES_CONTAINER="${SERVICE_NAME}-postgres-dev"
DOCKER_NETWORK="${SERVICE_NAME}-dev-net"

REMOTE_ROOT="/srv/${SERVICE_NAME}-dev"
REMOTE_POSTGRES_DATA_DIR="${REMOTE_ROOT}/postgres/data"
REMOTE_ENV_DIR="${REMOTE_ROOT}/env"
REMOTE_POSTGRES_ENV_FILE="${REMOTE_ENV_DIR}/postgres.env"

# dev-demo intentionally exposes PostgreSQL to the trusted LAN.
# Bind to the known LAN IP instead of 0.0.0.0.
REMOTE_DB_PORT_BIND="${DEV_DEMO_LAN_IP}:5432:5432"

ssh "$TARGET_HOST" "sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP"
SERVICE_NAME="$SERVICE_NAME"
POSTGRES_IMAGE="$POSTGRES_IMAGE"
POSTGRES_CONTAINER="$POSTGRES_CONTAINER"
DOCKER_NETWORK="$DOCKER_NETWORK"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_POSTGRES_DATA_DIR="$REMOTE_POSTGRES_DATA_DIR"
REMOTE_ENV_DIR="$REMOTE_ENV_DIR"
REMOTE_POSTGRES_ENV_FILE="$REMOTE_POSTGRES_ENV_FILE"
REMOTE_DB_PORT_BIND="$REMOTE_DB_PORT_BIND"

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
  echo "Error: docker is required on \$TARGET_ENV."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: docker is not available to the current SSH user."
  exit 1
fi

mkdir -p "\$REMOTE_POSTGRES_DATA_DIR"
mkdir -p "\$REMOTE_ENV_DIR"

if [ ! -f "\$REMOTE_POSTGRES_ENV_FILE" ]; then
  umask 077
  POSTGRES_PASSWORD="\$(openssl rand -hex 32 | tr -d '\n')"

  cat > "\$REMOTE_POSTGRES_ENV_FILE" <<ENVEOF
POSTGRES_DB=fastapi_is_cool
POSTGRES_USER=fastapi_is_cool
POSTGRES_PASSWORD=\$POSTGRES_PASSWORD
ENVEOF

  chmod 600 "\$REMOTE_POSTGRES_ENV_FILE"
  echo "Created dev PostgreSQL env file: \$REMOTE_POSTGRES_ENV_FILE"
else
  echo "Found existing dev PostgreSQL env file."
fi

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
    -p "\$REMOTE_DB_PORT_BIND" \\
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
    echo "LAN endpoint: \$DEV_DEMO_LAN_IP:5432"
    echo "Docker network endpoint: \$POSTGRES_CONTAINER:5432"
    exit 0
  fi

  sleep 1
done

echo "PostgreSQL did not become ready in time."
exit 1
EOF
