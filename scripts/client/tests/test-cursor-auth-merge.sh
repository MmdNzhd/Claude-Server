#!/bin/bash
# test-cursor-auth-merge.sh - Mac cursor auth merge must not use broken pipe+heredoc stdin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GIT="$ROOT/scripts/client/git-mode.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$GIT" ] || fail "git-mode.sh missing"
grep -q 'cursor_sqlite3_available' "$GIT" || fail 'merge must use sqlite3 CLI'
! grep -q 'merge_cursor_auth_into_local_db.*python3' "$GIT" || fail 'merge must not use python3'
grep -q 'merge_cursor_auth_into_local_db' "$GIT" || fail 'missing merge_cursor_auth_into_local_db'
! grep -q 'printf.*_CURSOR_AUTH_VALUES.*| python3 -' "$GIT" || fail 'broken pipe+python3 - stdin pattern'
! grep -q 'json.loads(sys.stdin.read())' "$GIT" || fail 'must not read auth JSON from stdin with heredoc script'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
db="$tmpdir/state.vscdb"
payload='{"cursorAuth/accessToken":"tok","cursorAuth/refreshToken":"ref","cursorAuth/cachedEmail":"u@test","cursorAuth/stripeMembershipType":"pro","storage.serviceMachineId":"machine-id-001"}'

export ALIAS=claude-server CFG_DIR="$tmpdir" CM='claude-mount'
# shellcheck disable=SC1090
source "$GIT"

merge_cursor_auth_into_local_db "$tmpdir" "$payload" || fail 'merge_cursor_auth_into_local_db failed'
local_cursor_auth_complete "$db" || fail 'tokens not written to state.vscdb'

echo 'OK test-cursor-auth-merge.sh'
