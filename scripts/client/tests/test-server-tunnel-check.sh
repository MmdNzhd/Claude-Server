#!/bin/bash
# test-server-tunnel-check.sh — static checks for server-side tunnel verification
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MOUNT="$ROOT/scripts/server/claude-mount.sh"
GIT_SETUP="$ROOT/scripts/server/claude-git-setup.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$MOUNT" ] || fail "claude-mount.sh missing"
[ -f "$GIT_SETUP" ] || fail "claude-git-setup.sh missing"

grep -q '_tunnel_banner_matches_laptop' "$MOUNT" || fail 'mount: missing banner check'
grep -q '_tunnel_auth_ok' "$MOUNT" || fail 'mount: missing auth check'
grep -q 'cmd_tunnel_status' "$MOUNT" || fail 'mount: missing tunnel-status command'
grep -q 'tunnel-status' "$MOUNT" || fail 'mount: tunnel-status not in dispatch'
grep -q 'another laptop' "$MOUNT" || fail 'mount: stale port error message missing'
grep -q '_tunnel_banner_matches_laptop' "$GIT_SETUP" || fail 'git-setup: missing banner check'

bash -n "$MOUNT" || fail "bash -n claude-mount.sh"
bash -n "$GIT_SETUP" || fail "bash -n claude-git-setup.sh"

echo 'OK test-server-tunnel-check.sh'
