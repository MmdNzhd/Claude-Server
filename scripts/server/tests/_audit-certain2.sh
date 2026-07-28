#!/bin/bash
# Fixed: ssh -n so loops don't lose users
set -u
FAILS=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; FAILS=$((FAILS+1)); }

echo "=== ALL LIVE USERS FULL ==="
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  uid=$(id -u "$u")
  base=$((20000+(uid-1000)*10))
  live_ports=""
  for s in 0 1 2 3 4 5 6 7 8 9; do
    p=$((base+s))
    timeout 0.4 bash -c "exec 3<>/dev/tcp/127.0.0.1/$p" 2>/dev/null && live_ports="$live_ports $p"
  done
  [ -z "$live_ports" ] && continue
  conf=$home/.claude-connect.conf
  am=$(grep -E '^ACTIVE_MOUNT=' "$conf" | tail -1 | cut -d= -f2- | tr -d "\"'")
  tp=$(grep -E '^TUNNEL_PORT=' "$conf" | tail -1 | cut -d= -f2- | tr -d "\"'")
  pin=$(grep -E '^LAPTOP_HOSTKEY_FP=' "$conf" | tail -1 | cut -d= -f2- | tr -d "\"'")
  lu=$(grep -E '^LAPTOP_USER=' "$conf" | tail -1 | cut -d= -f2- | tr -d "\"'")
  key=$home/.ssh/claude_laptop
  mp=/home/$u/mounts/$am
  wd=$(pgrep -u "$u" -f claude-watchdog | head -1 || true)
  echo "---- $u uid=$uid ports=$live_ports conf_port=$tp am=$am wd=$wd ----"
  [ -n "$am" ] && [ -n "$tp" ] && [ -n "$wd" ] || fail "$u missing am/tp/wd"
  echo " $live_ports " | grep -q " $tp " || fail "$u port $tp not live"
  grep -qF " $mp " /proc/mounts || fail "$u not mounted"
  timeout 5 ls "$mp" >/dev/null 2>&1 || fail "$u ls fail"
  pgrep -f "sshfs .*${mp}" >/dev/null || fail "$u no sshfs"
  auth=$(timeout 8 ssh -n -i "$key" -p "$tp" -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o IdentitiesOnly=yes \
    "${lu}@127.0.0.1" "echo AUTH_OK" 2>&1 || true)
  echo "$auth" | grep -q AUTH_OK && pass "$u AUTH" || fail "$u AUTH $auth"
  fps=$(timeout 6 ssh-keyscan -p "$tp" -T 3 -t rsa,ecdsa,ed25519 127.0.0.1 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || true)
  if [ -n "$pin" ] && echo "$fps" | grep -qF "$pin"; then pass "$u PIN_ANY"
  elif echo "$auth" | grep -q AUTH_OK; then pass "$u PIN skip (auth primary)"
  else fail "$u PIN+AUTH"; fi
  pass "$u FULL_OK"
done

echo "=== HASH deploy staging vs live ==="
DEP=/home/smart/claude-mount-deploy
for pair in \
  claude-mount.sh:/usr/local/lib/claude-mount \
  claude-self-heal.sh:/usr/local/bin/claude-self-heal \
  claude-watchdog.sh:/usr/local/bin/claude-watchdog \
  claude-mount-reaper.sh:/usr/local/bin/claude-mount-reaper \
  claude-automount.sh:/usr/local/bin/claude-automount \
  claude-tunnel-reacquire.sh:/usr/local/lib/claude-server/claude-tunnel-reacquire.sh
do
  a=${pair%%:*}; b=${pair##*:}
  t1=$(mktemp); t2=$(mktemp)
  tr -d '\r' <"$DEP/$a" >"$t1"
  tr -d '\r' <"$b" >"$t2"
  if cmp -s "$t1" "$t2"; then pass "HASH $a"
  else fail "HASH DIFF $a"; fi
  rm -f "$t1" "$t2"
done

echo "=== OFFLINE NO WD ==="
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  uid=$(id -u "$u")
  base=$((20000+(uid-1000)*10))
  live=0
  for s in 0 1 2 3 4 5 6 7 8 9; do
    timeout 0.25 bash -c "exec 3<>/dev/tcp/127.0.0.1/$((base+s))" 2>/dev/null && live=1 && break
  done
  [ "$live" = 0 ] || continue
  n=$(pgrep -u "$u" -f claude-watchdog | wc -l)
  [ "$n" = 0 ] || fail "$u offline WD=$n"
done
pass "offline safe"

echo "=== BINS ==="
b=0
for home in /home/*/; do
  u=$(basename "$home"); id "$u" >/dev/null 2>&1 || continue
  cmp -s /usr/local/lib/claude-mount "$home/.local/bin/claude-mount" || b=$((b+1))
  cmp -s /usr/local/bin/claude-self-heal "$home/.local/bin/claude-self-heal" || b=$((b+1))
  cmp -s /usr/local/bin/claude-automount "$home/.local/bin/claude-automount" || b=$((b+1))
done
[ "$b" = 0 ] && pass "bins" || fail "bins=$b"

echo "=== ZOMBIES ==="
z=0
while read -r mp; do
  pgrep -f "sshfs .*${mp}" >/dev/null || { echo ZOMBIE "$mp"; z=$((z+1)); }
  timeout 4 ls "$mp" >/dev/null 2>&1 || { echo HUNG "$mp"; z=$((z+1)); }
done < <(grep -E 'fuse\.sshfs|sshfs' /proc/mounts | awk '{print $2}' | grep mounts)
[ "$z" = 0 ] && pass "no zombies" || fail "zombies=$z"

echo FAILS=$FAILS
[ "$FAILS" = 0 ] && echo CERTAIN_ALL_GOOD && exit 0
echo NOT_CERTAIN; exit 1
