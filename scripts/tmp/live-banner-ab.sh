#!/bin/bash
PORT=21003
echo "=== LIVE port $PORT ==="
ss -ltn 2>/dev/null | grep -E ":${PORT}|:22" || true
echo
echo "--- A: current double-connect probe ---"
for i in 1 2 3 4 5 6 7 8; do
  t0=$(date +%s%3N)
  out=$(timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT 2>/dev/null && timeout 2 nc 127.0.0.1 $PORT 2>/dev/null | head -1" 2>/dev/null)
  ec=$?
  t1=$(date +%s%3N)
  echo "A$i exit=$ec ms=$((t1-t0)) banner=[${out}]"
done
echo
echo "--- B: single /dev/tcp read ---"
for i in 1 2 3 4 5 6 7 8; do
  t0=$(date +%s%3N)
  out=$(timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3; printf '%s' \"\$line\"" 2>/dev/null)
  ec=$?
  t1=$(date +%s%3N)
  echo "B$i exit=$ec ms=$((t1-t0)) banner=[${out}]"
done
echo
echo "--- C: nc -w2 only ---"
for i in 1 2 3 4 5 6 7 8; do
  t0=$(date +%s%3N)
  out=$(timeout 3 nc -w 2 127.0.0.1 "$PORT" 2>/dev/null | head -1)
  ec=$?
  t1=$(date +%s%3N)
  echo "C$i exit=$ec ms=$((t1-t0)) banner=[${out}]"
done
echo
echo "--- D: 10 parallel double-connect ---"
for i in $(seq 1 10); do
  (
    out=$(timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT 2>/dev/null && timeout 2 nc 127.0.0.1 $PORT 2>/dev/null | head -1" 2>/dev/null)
    echo "D$i banner=[${out}]"
  ) &
done
wait
echo
echo "--- E: prove reverse SSH works ---"
timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null -i ~/.ssh/claude_laptop -p "$PORT" \
  "Smart@127.0.0.1" "echo SSH_OK" 2>/dev/null || echo "SSH_FAIL ec=$?"
