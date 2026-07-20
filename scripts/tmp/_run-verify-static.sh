#!/usr/bin/env bash
set +e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0
live_skip=0
for t in "$ROOT/scripts/client/tests"/test-*.sh; do
  [ -f "$t" ] || continue
  base="$(basename "$t")"
  case "$base" in
    *live*) echo "LIVE-SKIP: $base"; live_skip=1; continue ;;
  esac
  echo "--- $base ---"
  TMP=$(mktemp)
  tr -d '\r' < "$t" > "$TMP"
  bash "$TMP"
  rc=$?
  rm -f "$TMP"
  if [ "$rc" -eq 0 ]; then
    echo "OK $base"
  else
    echo "FAILED: $base exit $rc"
    fail=1
  fi
  echo ""
done
echo "VERIFY_STATIC_FAIL=$fail LIVE_SKIP=$live_skip"
exit $fail
