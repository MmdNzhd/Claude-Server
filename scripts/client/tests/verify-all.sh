#!/bin/bash
# verify-all.sh — run every static + live connect verification (Mac)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

echo "=== Claude Connect verify-all ==="
echo ""

fail=0
for t in "$ROOT/scripts/client/tests"/test-*.sh; do
    [ -f "$t" ] || continue
    base="$(basename "$t")"
    [ "$base" = "verify-all.sh" ] && continue
    [ "$base" = "test-connect-pipeline.ps1" ] && continue
    [ "$base" = "test-git-mode-deep.ps1" ] && continue
    echo "--- ${base} ---"
    if bash "$t"; then
        echo ""
    else
        fail=1
        echo "FAILED: $base" >&2
        break
    fi
done

PUB="$HOME/Desktop/claude-publish/claude-code-client-20260704"
if [ -d "$PUB" ]; then
    echo "--- publish sync ---"
    for pair in \
        "scripts/client/mac/connect.sh:mac/connect.sh" \
        "scripts/client/git-mode.sh:mac/git-mode.sh" \
        "scripts/server/claude-mount.sh:mac/claude-mount.sh" \
        "scripts/client/windows/connect.ps1:windows/connect.ps1" \
        "scripts/client/git-mode.ps1:windows/git-mode.ps1"; do
        a="$ROOT/${pair%%:*}"
        b="$PUB/${pair##*:}"
        if cmp -s "$a" "$b" 2>/dev/null; then
            echo "OK  ${pair##*:}"
        else
            echo "MISMATCH ${pair##*:}" >&2
            fail=1
        fi
    done
    echo ""
fi

if [ "$fail" -eq 0 ]; then
    echo "VERIFY-ALL PASSED"
    exit 0
fi
echo "VERIFY-ALL FAILED"
exit 1
