#!/bin/bash
set -u
bad=0
echo "=== LIVE ==="
for u in amir mehrdad smart; do
  conf=/home/$u/.claude-connect.conf
  am=$(grep -E '^ACTIVE_MOUNT=' "$conf" | tail -1 | cut -d= -f2- | tr -d "\"'")
  tp=$(grep -E '^TUNNEL_PORT=' "$conf" | tail -1 | cut -d= -f2- | tr -d "\"'")
  mp="/home/$u/mounts/$am"
  wd=$(pgrep -u "$u" -f claude-watchdog | head -1 || true)
  ok=1
  grep -qF " $mp " /proc/mounts || ok=0
  timeout 3 ls "$mp" >/dev/null 2>&1 || ok=0
  [ -n "$wd" ] || ok=0
  [ -n "$tp" ] || ok=0
  echo "$u am=$am tp=$tp wd=$wd ok=$ok"
  [ "$ok" = 1 ] || bad=$((bad + 1))
done

echo "=== BINS ==="
b=0
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  for pair in \
    "/usr/local/lib/claude-mount:$home/.local/bin/claude-mount" \
    "/usr/local/bin/claude-self-heal:$home/.local/bin/claude-self-heal" \
    "/usr/local/bin/claude-automount:$home/.local/bin/claude-automount"
  do
    src=${pair%%:*}
    dst=${pair##*:}
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
      echo "STALE $dst"
      b=$((b + 1))
    fi
  done
done
echo "bin_bad=$b"

echo "=== ZOMBIES ==="
z=0
while read -r mp; do
  [ -z "$mp" ] && continue
  if ! pgrep -f "sshfs .*${mp}" >/dev/null 2>&1; then
    echo "ZOMBIE $mp"
    z=$((z + 1))
  elif ! timeout 3 ls "$mp" >/dev/null 2>&1; then
    echo "HUNG $mp"
    z=$((z + 1))
  else
    echo "OK $mp"
  fi
done < <(grep -E 'fuse\.sshfs|sshfs' /proc/mounts | awk '{print $2}' | grep '/mounts/')
echo "zombie_bad=$z"

echo "=== GATES ==="
gates=1
grep -q TUNNEL_PORT_REACQUIRED /usr/local/bin/claude-self-heal || gates=0
grep -q tunnel_up_effective /usr/local/bin/claude-watchdog || gates=0
grep -q fusermount /usr/local/bin/claude-mount-reaper || gates=0
grep -q MIN_AGE_SECONDS /usr/local/bin/claude-mount-reaper || gates=0
grep -q leftover /usr/local/lib/claude-mount || gates=0
grep -q tunnel_up_effective /usr/local/lib/claude-server/claude-tunnel-reacquire.sh || gates=0
echo "gates=$gates"

echo "=== OFFLINE NOTE ==="
# Offline users may keep ACTIVE_MOUNT + leftover dirs; that is OK until reconnect.
offline=0
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  uid=$(id -u "$u")
  base=$((20000 + (uid - 1000) * 10))
  live=0
  for s in 0 1 2 3 4 5 6 7 8 9; do
    timeout 0.25 bash -c "exec 3<>/dev/tcp/127.0.0.1/$((base + s))" 2>/dev/null && live=1 && break
  done
  if [ "$live" = 0 ]; then
    offline=$((offline + 1))
  fi
done
echo "offline_users=$offline (no WD expected)"

if [ "$bad" = 0 ] && [ "$b" = 0 ] && [ "$z" = 0 ] && [ "$gates" = 1 ]; then
  echo FINAL=ALL_GOOD
  exit 0
fi
echo "FINAL=ISSUES live=$bad bins=$b zombies=$z gates=$gates"
exit 1
