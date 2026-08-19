#!/usr/bin/env sh
set -eu

SOURCE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEV_DEMO_HOST_OVERRIDE="${DEV_DEMO_HOST-}"
DEV_DEMO_LAN_IP_OVERRIDE="${DEV_DEMO_LAN_IP-}"
BUILD_CLONE_ROOT_WSL_OVERRIDE="${BUILD_CLONE_ROOT_WSL-}"
BUILD_ARTIFACT_DIR_WSL_OVERRIDE="${BUILD_ARTIFACT_DIR_WSL-}"

if [ -f "$SOURCE_ROOT/scripts/env/dev-demo.env" ]; then
  . "$SOURCE_ROOT/scripts/env/dev-demo.env"
elif [ -f "$SOURCE_ROOT/scripts/env/dev-demo.local.env" ]; then
  . "$SOURCE_ROOT/scripts/env/dev-demo.local.env"
fi

if [ -n "$DEV_DEMO_HOST_OVERRIDE" ]; then
  DEV_DEMO_HOST="$DEV_DEMO_HOST_OVERRIDE"
fi

if [ -n "$DEV_DEMO_LAN_IP_OVERRIDE" ]; then
  DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP_OVERRIDE"
fi

if [ -n "$BUILD_CLONE_ROOT_WSL_OVERRIDE" ]; then
  BUILD_CLONE_ROOT_WSL="$BUILD_CLONE_ROOT_WSL_OVERRIDE"
fi

if [ -n "$BUILD_ARTIFACT_DIR_WSL_OVERRIDE" ]; then
  BUILD_ARTIFACT_DIR_WSL="$BUILD_ARTIFACT_DIR_WSL_OVERRIDE"
fi

SERVICE_NAME="${SERVICE_NAME:-fastapi-is-cool}"
BUILD_CLONE_ROOT_WSL="${BUILD_CLONE_ROOT_WSL:-/mnt/j/deploy_remote_repo}"
BUILD_ARTIFACT_DIR_WSL="${BUILD_ARTIFACT_DIR_WSL:-$BUILD_CLONE_ROOT_WSL/artifacts}"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required to build the image."
  exit 1
fi

if ! git -C "$SOURCE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: this script must run from a git checkout."
  exit 1
fi

if [ -n "$(git -C "$SOURCE_ROOT" status --porcelain)" ]; then
  echo "Error: source checkout has uncommitted changes."
  echo "Commit and push the generated baseline before building from the clean clone."
  echo
  echo "Suggested check:"
  echo "  git status --short"
  exit 1
fi

REMOTE_URL="$(git -C "$SOURCE_ROOT" config --get remote.origin.url || true)"
if [ -z "$REMOTE_URL" ]; then
  echo "Error: remote.origin.url is required to prepare a clean build clone."
  exit 1
fi

BRANCH="$(git -C "$SOURCE_ROOT" branch --show-current)"
if [ -z "$BRANCH" ]; then
  echo "Error: source checkout must be on a branch."
  exit 1
fi

UPSTREAM="$(git -C "$SOURCE_ROOT" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)"
if [ -z "$UPSTREAM" ]; then
  echo "Error: current branch has no upstream."
  echo "Push the branch before building from the clean clone."
  echo
  echo "Suggested command:"
  echo "  git push -u origin $BRANCH"
  exit 1
fi

git -C "$SOURCE_ROOT" fetch origin "$BRANCH"

LOCAL_HEAD="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
UPSTREAM_HEAD="$(git -C "$SOURCE_ROOT" rev-parse "$UPSTREAM")"

if [ "$LOCAL_HEAD" != "$UPSTREAM_HEAD" ]; then
  echo "Error: local HEAD is not the same as upstream $UPSTREAM."
  echo "Commit and push the generated baseline before building from the clean clone."
  echo
  echo "Suggested command:"
  echo "  git push"
  exit 1
fi

mkdir -p "$(dirname "$BUILD_CLONE_ROOT_WSL")"

if [ ! -d "$BUILD_CLONE_ROOT_WSL/.git" ]; then
  if [ -e "$BUILD_CLONE_ROOT_WSL" ]; then
    echo "Error: build clone root exists but is not a git repository: $BUILD_CLONE_ROOT_WSL"
    exit 1
  fi

  git clone --branch "$BRANCH" "$REMOTE_URL" "$BUILD_CLONE_ROOT_WSL"
else
  if [ -n "$(git -C "$BUILD_CLONE_ROOT_WSL" status --porcelain)" ]; then
    echo "Error: build clone has uncommitted changes: $BUILD_CLONE_ROOT_WSL"
    exit 1
  fi

  git -C "$BUILD_CLONE_ROOT_WSL" fetch origin "$BRANCH"
  git -C "$BUILD_CLONE_ROOT_WSL" checkout "$BRANCH"
  git -C "$BUILD_CLONE_ROOT_WSL" pull --ff-only origin "$BRANCH"
fi

for required_path in pyproject.toml uv.lock app alembic alembic.ini Dockerfile; do
  if [ ! -e "$BUILD_CLONE_ROOT_WSL/$required_path" ]; then
    echo "Error: missing required build input in clean clone: $required_path"
    echo "Run bootstrap scripts and commit/push the generated baseline before building."
    exit 1
  fi
done

COMMIT_SHA="$(git -C "$BUILD_CLONE_ROOT_WSL" rev-parse HEAD)"
SHORT_SHA="$(git -C "$BUILD_CLONE_ROOT_WSL" rev-parse --short=12 HEAD)"
IMAGE_TAG="${IMAGE_TAG:-$SERVICE_NAME:$SHORT_SHA}"
TAR_FILE="${TAR_FILE:-$BUILD_ARTIFACT_DIR_WSL/$SERVICE_NAME-$SHORT_SHA.tar}"

mkdir -p "$BUILD_ARTIFACT_DIR_WSL"

echo "Building image from clean clone:"
echo "  clone: $BUILD_CLONE_ROOT_WSL"
echo "  commit: $COMMIT_SHA"
echo "  image: $IMAGE_TAG"
echo "  tar: $TAR_FILE"

docker build \
  --label "org.opencontainers.image.revision=$COMMIT_SHA" \
  --tag "$IMAGE_TAG" \
  "$BUILD_CLONE_ROOT_WSL"

docker save --output "$TAR_FILE" "$IMAGE_TAG"

echo
echo "Image tarball created:"
echo "  $TAR_FILE"
echo
echo "Next step:"
echo "  IMAGE_TAR=\"$TAR_FILE\" scripts/dev-demo/deploy-app.sh"
echo
echo "If you are deploying from outside the trusted LAN, you may skip the dev-demo path and continue with:"
echo "  scripts/aws-demo/setup-env.sh"
