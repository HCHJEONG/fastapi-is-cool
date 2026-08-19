#!/usr/bin/env sh
set -eu

TARGET_ENV="dev-demo"
TARGET_HOST="yoga"
DEV_DEMO_LAN_IP="192.168.0.104"

SERVICE_NAME="fastapi-is-cool"
POSTGRES_CONTAINER="${SERVICE_NAME}-postgres-dev"

REMOTE_ROOT="/srv/${SERVICE_NAME}-dev"
REMOTE_ENV_DIR="${REMOTE_ROOT}/env"
REMOTE_APP_ENV_FILE="${REMOTE_ENV_DIR}/app.env"
REMOTE_POSTGRES_ENV_FILE="${REMOTE_ENV_DIR}/postgres.env"

ssh "$TARGET_HOST" "sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP"
POSTGRES_CONTAINER="$POSTGRES_CONTAINER"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_ENV_DIR="$REMOTE_ENV_DIR"
REMOTE_APP_ENV_FILE="$REMOTE_APP_ENV_FILE"
REMOTE_POSTGRES_ENV_FILE="$REMOTE_POSTGRES_ENV_FILE"

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

mkdir -p "\$REMOTE_ENV_DIR"
chmod 700 "\$REMOTE_ENV_DIR"

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
  chmod 600 "\$REMOTE_POSTGRES_ENV_FILE"
  echo "Found existing dev PostgreSQL env file: \$REMOTE_POSTGRES_ENV_FILE"
fi

POSTGRES_PASSWORD="\$(sed -n 's/^POSTGRES_PASSWORD=//p' "\$REMOTE_POSTGRES_ENV_FILE" | head -n 1)"

if [ ! -f "\$REMOTE_APP_ENV_FILE" ]; then
  umask 077
  cat > "\$REMOTE_APP_ENV_FILE" <<ENVEOF
APP_ENV=dev-demo
LOG_LEVEL=debug
DATABASE_URL=postgresql+asyncpg://fastapi_is_cool:\$POSTGRES_PASSWORD@\$POSTGRES_CONTAINER:5432/fastapi_is_cool
DATABASE_LAN_HOST=\$DEV_DEMO_LAN_IP
DATABASE_LAN_PORT=5432
ENVEOF

  chmod 600 "\$REMOTE_APP_ENV_FILE"
  echo "Created dev app env file: \$REMOTE_APP_ENV_FILE"
else
  chmod 600 "\$REMOTE_APP_ENV_FILE"
  echo "Found existing dev app env file: \$REMOTE_APP_ENV_FILE"
fi
EOF
