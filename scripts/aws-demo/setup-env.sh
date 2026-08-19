#!/usr/bin/env sh
set -eu

TARGET_ENV="aws-demo"
TARGET_HOST="aws-demo"

SERVICE_NAME="fastapi-is-cool"
REMOTE_ROOT="/srv/${SERVICE_NAME}"
REMOTE_ENV_DIR="${REMOTE_ROOT}/env"
REMOTE_APP_ENV_FILE="${REMOTE_ENV_DIR}/app.env"
REMOTE_POSTGRES_ENV_FILE="${REMOTE_ENV_DIR}/postgres.env"
REMOTE_APP_ENV_TEMPLATE="${REMOTE_ENV_DIR}/app.env.example"
REMOTE_POSTGRES_ENV_TEMPLATE="${REMOTE_ENV_DIR}/postgres.env.example"

ssh "$TARGET_HOST" "sudo sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_ENV_DIR="$REMOTE_ENV_DIR"
REMOTE_APP_ENV_FILE="$REMOTE_APP_ENV_FILE"
REMOTE_POSTGRES_ENV_FILE="$REMOTE_POSTGRES_ENV_FILE"
REMOTE_APP_ENV_TEMPLATE="$REMOTE_APP_ENV_TEMPLATE"
REMOTE_POSTGRES_ENV_TEMPLATE="$REMOTE_POSTGRES_ENV_TEMPLATE"

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

mkdir -p "\$REMOTE_ENV_DIR"
chmod 700 "\$REMOTE_ENV_DIR"

if [ ! -f "\$REMOTE_POSTGRES_ENV_TEMPLATE" ]; then
  cat > "\$REMOTE_POSTGRES_ENV_TEMPLATE" <<'ENVEOF'
POSTGRES_DB=fastapi_is_cool
POSTGRES_USER=fastapi_is_cool
POSTGRES_PASSWORD=<strong-production-like-password>
ENVEOF
  chmod 600 "\$REMOTE_POSTGRES_ENV_TEMPLATE"
  echo "Created template: \$REMOTE_POSTGRES_ENV_TEMPLATE"
fi

if [ ! -f "\$REMOTE_APP_ENV_TEMPLATE" ]; then
  cat > "\$REMOTE_APP_ENV_TEMPLATE" <<'ENVEOF'
APP_ENV=aws-demo
LOG_LEVEL=info
DATABASE_URL=postgresql+asyncpg://fastapi_is_cool:<password>@fastapi-is-cool-postgres:5432/fastapi_is_cool
ENVEOF
  chmod 600 "\$REMOTE_APP_ENV_TEMPLATE"
  echo "Created template: \$REMOTE_APP_ENV_TEMPLATE"
fi

if [ -f "\$REMOTE_POSTGRES_ENV_FILE" ]; then
  chmod 600 "\$REMOTE_POSTGRES_ENV_FILE"
  echo "Found existing PostgreSQL env file: \$REMOTE_POSTGRES_ENV_FILE"
else
  echo "Missing required PostgreSQL env file: \$REMOTE_POSTGRES_ENV_FILE"
  echo "Create it manually from: \$REMOTE_POSTGRES_ENV_TEMPLATE"
fi

if [ -f "\$REMOTE_APP_ENV_FILE" ]; then
  chmod 600 "\$REMOTE_APP_ENV_FILE"
  echo "Found existing app env file: \$REMOTE_APP_ENV_FILE"
else
  echo "Missing app env file: \$REMOTE_APP_ENV_FILE"
  echo "Create it manually from: \$REMOTE_APP_ENV_TEMPLATE"
fi
EOF
