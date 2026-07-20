#!/usr/bin/env bash
# Run client test-*.sh with correct $0 depth (LF copy beside original).
set +e
cd "$(dirname "$0")/../.." || exit 99
REPO="$(pwd)"
echo "REPO=$REPO"
GITBASH="${GITBASH:-}"

run_one() {
  local src="$1"
  local base name lf
  base="$(basename "$src")"
  lf="${src}.lf-gate"
  tr -d '\r' < "$src" > "$lf"
  echo "--- $base ---"
  bash "$lf"
  local rc=$?
  rm -f "$lf"
  return $rc
}

MODE="${1:-all}"

if [ "$MODE" = "win-connect" ] || [ "$MODE" = "all" ]; then
  echo "=== GATE7 test-windows-connect (LF copy) ==="
  run_one "scripts/client/tests/test-windows-connect.sh"
  echo "EXIT_WIN_CONNECT_LF=$?"
  echo ""
  echo "=== GATE7 native (no CRLF strip) ==="
  bash "scripts/client/tests/test-windows-connect.sh"
  echo "EXIT_WIN_CONNECT_NATIVE=$?"
  echo ""
fi

if [ "$MODE" = "verify" ] || [ "$MODE" = "all" ]; then
  echo "=== GATE4 verify-all static (skip *live*) ==="
  fail=0
  live_skip=0
  for t in scripts/client/tests/test-*.sh; do
    [ -f "$t" ] || continue
    base="$(basename "$t")"
    case "$base" in
      *live*) echo "LIVE-SKIP: $base"; live_skip=1; continue ;;
    esac
    if run_one "$t"; then
      echo "OK $base"
    else
      echo "FAILED: $base exit $?"
      fail=1
    fi
    echo ""
  done
  echo "VERIFY_STATIC_FAIL=$fail LIVE_SKIP=$live_skip"
  exit $fail
fi
