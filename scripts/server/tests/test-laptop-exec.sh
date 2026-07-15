#!/usr/bin/env bash
# test-laptop-exec.sh - regression (requires live connect session)
set -euo pipefail
LE="${LE:-$HOME/.local/bin/laptop-exec}"
[ -x "$LE" ] || LE="/usr/local/bin/laptop-exec"
[ -x "$LE" ] || { echo "laptop-exec not found"; exit 1; }
echo "=== laptop-exec regression ==="
echo "binary: $LE"
"$LE" test
