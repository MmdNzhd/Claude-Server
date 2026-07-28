#!/bin/bash
# test-b1-reaper-pass3.sh — wrapper (≥50 asserts in Python suite B1)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 "$HERE/test-mount-heal-hard-all.py" 2>&1 | tee /tmp/mount-heal-all.out | grep -E 'SUITE=B1|FAIL \[B1\]|TOTAL_'
grep -q 'SUITE=B1' /tmp/mount-heal-all.out
grep 'ASSERTS=' /tmp/mount-heal-all.out | grep 'SUITE=B1' | grep -q 'FAILS=0'
