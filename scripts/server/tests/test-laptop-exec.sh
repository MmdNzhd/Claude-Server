#!/usr/bin/env bash
# test-laptop-exec.sh - regression tests for laptop-exec (requires live connect session)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LE="${LE:-$HOME/.local/bin/laptop-exec}"
[ -x "$LE" ] || LE="/usr/local/bin/laptop-exec"
[ -x "$LE" ] || LE="$SCRIPT_DIR/../laptop-exec.sh"

pass=0
fail=0

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS  $name"
        pass=$((pass + 1))
    else
        echo "FAIL  $name"
        fail=$((fail + 1))
    fi
}

echo "=== laptop-exec regression ==="
echo "binary: $LE"
[ -x "$LE" ] || { echo "laptop-exec not found"; exit 1; }

check "status" "$LE" status
check "git status" "$LE" git -- status
check "read file" "$LE" read CLAUDE.md
check "read nested path" "$LE" read scripts/server/laptop-exec.sh
check "rg untracked" "$LE" rg "laptop-exec self-test"
check "dotnet" "$LE" run -- dotnet --version

if [ -f "$HOME/.claude-mounts.d/review.conf" ]; then
    if "$LE" git -p review -- status >/dev/null 2>&1; then
        check "git review" "$LE" git -p review -- status
    else
        echo "SKIP  git review (no git on laptop path)"
    fi
fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
