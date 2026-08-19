#!/usr/bin/env sh
set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEV_DEMO_HOST_OVERRIDE="${DEV_DEMO_HOST-}"
AWS_DEMO_HOST_OVERRIDE="${AWS_DEMO_HOST-}"
DEV_DEMO_LAN_IP_OVERRIDE="${DEV_DEMO_LAN_IP-}"

if [ -f "$ROOT_DIR/scripts/env/dev-demo.env" ]; then
  . "$ROOT_DIR/scripts/env/dev-demo.env"
elif [ -f "$ROOT_DIR/scripts/env/dev-demo.local.env" ]; then
  . "$ROOT_DIR/scripts/env/dev-demo.local.env"
fi

if [ -f "$ROOT_DIR/scripts/env/aws-demo.env" ]; then
  . "$ROOT_DIR/scripts/env/aws-demo.env"
elif [ -f "$ROOT_DIR/scripts/env/aws-demo.local.env" ]; then
  . "$ROOT_DIR/scripts/env/aws-demo.local.env"
fi

if [ -n "$DEV_DEMO_HOST_OVERRIDE" ]; then
  DEV_DEMO_HOST="$DEV_DEMO_HOST_OVERRIDE"
fi

if [ -n "$AWS_DEMO_HOST_OVERRIDE" ]; then
  AWS_DEMO_HOST="$AWS_DEMO_HOST_OVERRIDE"
fi

if [ -n "$DEV_DEMO_LAN_IP_OVERRIDE" ]; then
  DEV_DEMO_LAN_IP="$DEV_DEMO_LAN_IP_OVERRIDE"
fi

DEV_DEMO_HOST="${DEV_DEMO_HOST:-yoga}"
AWS_DEMO_HOST="${AWS_DEMO_HOST:-aws-demo}"
DEV_DEMO_LAN_IP="${DEV_DEMO_LAN_IP:-192.168.0.104}"

FAILED=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  FAILED=1
}

warn() {
  echo "WARN: $1"
}

check_command() {
  name="$1"

  if command -v "$name" >/dev/null 2>&1; then
    pass "found local command: $name"
  else
    fail "missing local command: $name"
  fi
}

check_ssh() {
  host="$1"
  label="$2"

  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "printf ok" >/dev/null 2>&1; then
    pass "SSH works for $label: $host"
  else
    fail "SSH failed for $label: $host"
  fi
}

remote_command_succeeds() {
  host="$1"
  command_text="$2"

  ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "$command_text" >/dev/null 2>&1
}

check_remote_command() {
  host="$1"
  label="$2"
  command_text="$3"

  if remote_command_succeeds "$host" "$command_text"; then
    pass "$label"
    return 0
  fi

  fail "$label"
}

echo "Checking local prerequisites..."
check_command git
check_command ssh
check_command sh
check_command uv

if command -v uv >/dev/null 2>&1; then
  if uv python find 3.12 >/dev/null 2>&1; then
    pass "uv can find Python 3.12"
  else
    fail "uv cannot find Python 3.12; install Python 3.12 or make it available to uv"
  fi
fi

echo
echo "Checking SSH targets..."
check_ssh "$DEV_DEMO_HOST" "dev-demo"
check_ssh "$AWS_DEMO_HOST" "aws-demo"

echo
echo "Checking dev-demo remote prerequisites..."
check_remote_command \
  "$DEV_DEMO_HOST" \
  "dev-demo has Docker available without sudo" \
  "command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1"

if remote_command_succeeds \
  "$DEV_DEMO_HOST" \
  "hostname -I | tr ' ' '\n' | grep -qx '$DEV_DEMO_LAN_IP'"; then
  pass "dev-demo reports configured LAN IP $DEV_DEMO_LAN_IP"
else
  warn "dev-demo did not report configured LAN IP $DEV_DEMO_LAN_IP"
  warn "Override DEV_DEMO_LAN_IP when using a different internal server address."
fi

echo
echo "Checking aws-demo remote prerequisites..."
check_remote_command \
  "$AWS_DEMO_HOST" \
  "aws-demo has sudo Docker available" \
  "command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All prerequisite checks passed."
  exit 0
fi

echo "One or more prerequisite checks failed."
echo "Fix the failures above before running the bootstrap or deployment scripts."
exit 1
