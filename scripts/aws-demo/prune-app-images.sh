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
SERVICE_NAME="${SERVICE_NAME:-fastapi-is-cool}"
REMOTE_ROOT="/srv/${SERVICE_NAME}"
REMOTE_IMAGE_DIR="${REMOTE_ROOT}/images"

echo "Pruning unused app containers, images, and tarballs on aws-demo:"
echo "  host: $TARGET_HOST"
echo "  service: $SERVICE_NAME"
echo "  image tar directory: $REMOTE_IMAGE_DIR"

ssh "$TARGET_HOST" "sudo sh -s" <<EOF
set -eu

TARGET_ENV="$TARGET_ENV"
SERVICE_NAME="$SERVICE_NAME"
REMOTE_ROOT="$REMOTE_ROOT"
REMOTE_IMAGE_DIR="$REMOTE_IMAGE_DIR"

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
  echo "Error: docker is required on aws-demo."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: docker is not available through sudo on aws-demo."
  exit 1
fi

echo
echo "Removing stopped app containers..."
docker ps -a \
  --filter "status=created" \
  --filter "status=exited" \
  --filter "status=dead" \
  --format '{{.ID}} {{.Image}} {{.Names}}' |
while read -r container_id image_ref container_name; do
  [ -n "\$container_id" ] || continue

  case "\$image_ref:\$container_name" in
    "\$SERVICE_NAME:"*|*":\$SERVICE_NAME-app")
      docker rm "\$container_id"
      ;;
  esac
done

running_image_ids="\$(docker ps --format '{{.Image}}' |
while read -r image_ref; do
  [ -n "\$image_ref" ] || continue
  docker image inspect --format '{{.Id}}' "\$image_ref" 2>/dev/null || true
done | sort -u)"

echo
echo "Removing unused app images..."
docker images "\$SERVICE_NAME" --format '{{.Repository}}:{{.Tag}} {{.ID}}' |
while read -r image_ref image_id; do
  [ -n "\$image_ref" ] || continue

  if printf '%s\n' "\$running_image_ids" | grep -qx "\$image_id"; then
    echo "Keeping running image: \$image_ref"
  else
    docker image rm "\$image_ref" || true
  fi
done

echo
echo "Removing remote app image tarballs..."
if [ -d "\$REMOTE_IMAGE_DIR" ]; then
  find "\$REMOTE_IMAGE_DIR" -maxdepth 1 -type f -name "\$SERVICE_NAME-*.tar" -print -delete
else
  echo "Image tar directory does not exist: \$REMOTE_IMAGE_DIR"
fi

echo
echo "Remaining app images:"
docker images "\$SERVICE_NAME" || true
EOF
