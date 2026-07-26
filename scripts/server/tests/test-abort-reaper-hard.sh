#!/usr/bin/env bash
# test-abort-reaper-hard.sh - hard live gates on the server (run as smart with tunnel UP)
# Invoked by scripts/client/tests/test-abort-reaper-hard-live.ps1
set +e
N="${HARD_ABORT_N:-4}"
PASS=0; FAIL=0
ok() { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== HARD server gates (N=$N) ==="
echo ""

# H1 syntax + contracts
if bash -n /usr/local/bin/laptop-exec; then ok "H1 bash -n laptop-exec"; else bad "H1 bash -n laptop-exec"; fi
LE=/usr/local/bin/laptop-exec
miss=0
for pat in "_le_on_signal" "meaning=aborted" "_LE_CMD_CHILD" "taskkill.exe"; do
  grep -qF "$pat" "$LE" || { echo "    miss $pat"; miss=1; }
done
grep -q "trap '_le_on_signal' TERM INT HUP" "$LE" || miss=1
if grep -n '`"\$env:LE_JOB_ID' "$LE" | grep -q .; then echo "    backtick bug"; miss=1; fi
if [ "$miss" -eq 0 ]; then ok "H1 abort contracts"; else bad "H1 abort contracts"; fi

# H2 tunnel
st=$(laptop-exec status 2>&1)
echo "$st" | head -n 8
if echo "$st" | grep -qE 'tunnel:[[:space:]]*UP'; then ok "H2 tunnel UP"; else bad "H2 tunnel UP"; fi

# H3 parallel abort
pkill -f 'HARDABORT_SLEEP' 2>/dev/null || true
pkill -f 'laptop-exec run -p refactoreoldclub -- powershell' 2>/dev/null || true
sleep 1
rm -f /tmp/hard-le-*.pid /tmp/hard-to-*.pid /tmp/hard-ssh-*.pid
for i in $(seq 1 "$N"); do
  nohup laptop-exec run -p refactoreoldclub -- powershell -NoProfile -Command \
    "Write-Output ('HARDABORT_SLEEP_' + '$i'); Start-Sleep -Seconds 90" \
    >"/tmp/hard-le-$i.out" 2>&1 &
  echo $! >"/tmp/hard-bg-$i.pid"
done
sleep 6

# Map LE pids (laptop-exec bash, not nohup wrapper)
mapfile -t LES < <(ps -u smart -o pid=,cmd= | awk '/\/usr\/local\/bin\/laptop-exec run -p refactoreoldclub/ {print $1}')
echo "LE_PIDS=${LES[*]}"
echo "LE_COUNT=${#LES[@]}"
if [ "${#LES[@]}" -lt "$N" ]; then
  bad "H3 started ${#LES[@]}/$N LE runs"
  for i in $(seq 1 "$N"); do echo "--- out $i ---"; tail -n 5 "/tmp/hard-le-$i.out" 2>/dev/null; done
else
  ok "H3 started $N LE runs"
fi

i=0
for LE in "${LES[@]}"; do
  i=$((i+1))
  echo "$LE" >"/tmp/hard-le-$i.pid"
  TO=$(ps -o pid= --ppid "$LE" 2>/dev/null | awk '{print $1; exit}')
  SSH=$(ps -o pid= --ppid "$TO" 2>/dev/null | awk '{print $1; exit}')
  echo "$TO" >"/tmp/hard-to-$i.pid"
  echo "$SSH" >"/tmp/hard-ssh-$i.pid"
  echo "TREE i=$i LE=$LE TO=$TO SSH=$SSH"
done

for i in $(seq 1 "$i"); do
  LE=$(cat "/tmp/hard-le-$i.pid" 2>/dev/null)
  [ -n "$LE" ] && kill -TERM "$LE" 2>/dev/null
done
sleep 7

ssh_alive=0
le_alive=0
for i in $(seq 1 "${#LES[@]}"); do
  TO=$(cat "/tmp/hard-to-$i.pid" 2>/dev/null)
  SSH=$(cat "/tmp/hard-ssh-$i.pid" 2>/dev/null)
  LE=$(cat "/tmp/hard-le-$i.pid" 2>/dev/null)
  if [ -n "$TO" ] && kill -0 "$TO" 2>/dev/null; then echo "TO_ALIVE $TO"; ssh_alive=1; fi
  if [ -n "$SSH" ] && kill -0 "$SSH" 2>/dev/null; then echo "SSH_ALIVE $SSH"; ssh_alive=1; fi
  if [ -n "$LE" ] && kill -0 "$LE" 2>/dev/null; then echo "LE_ALIVE $LE (may be remote-kill cleanup)"; le_alive=1; fi
done
busy=0
for s in 0 1 2 3 4 5 6 7; do
  h=$(fuser "$HOME/.cache/laptop-exec/slot-$s.lock" 2>/dev/null | wc -w)
  busy=$((busy + h))
done
echo "SLOTS_BUSY=$busy LE_STILL=$le_alive"
# wait extra for LE cleanup to finish
sleep 8
le_alive2=0
for i in $(seq 1 "${#LES[@]}"); do
  LE=$(cat "/tmp/hard-le-$i.pid" 2>/dev/null)
  if [ -n "$LE" ] && kill -0 "$LE" 2>/dev/null; then le_alive2=1; echo "LE_STILL $LE"; fi
done
aborted=$(grep -c 'meaning=aborted' "$HOME/.claude/logs/connect-$(date +%Y%m%d).log" 2>/dev/null || echo 0)
echo "ABORTED_LOG_LINES=$aborted"
if [ "$ssh_alive" -eq 0 ] && [ "$busy" -eq 0 ]; then ok "H3 timeout/ssh dead + slots empty"; else bad "H3 ssh_alive=$ssh_alive slots=$busy"; fi
if [ "$le_alive2" -eq 0 ]; then ok "H3 all LE processes exited after abort"; else bad "H3 LE still alive after 15s"; fi

pkill -f 'HARDABORT_SLEEP' 2>/dev/null || true
pkill -f 'laptop-exec run -p refactoreoldclub -- powershell' 2>/dev/null || true

# H6/H7 reaper
out=$(/usr/local/bin/cursor-server-reaper --user smart --min-age 600 2>&1)
echo "$out" | grep -E 'protect|reap_candidate|reap_done' | tail -n 20
prot=$(echo "$out" | grep -c 'protect user=smart' || true)
n_sm=0; n_estab=0
while read -r pid et cmd; do
  case "$cmd" in *server-main.js*) ;; *) continue ;; esac
  n_sm=$((n_sm+1))
  est=$(ss -tnp 2>/dev/null | grep -c "pid=${pid}," || true)
  echo "SM pid=$pid age=$et estab=$est"
  [ "${est:-0}" -gt 0 ] && n_estab=$((n_estab+1))
done < <(ps -u smart -o pid=,etimes=,cmd=)
echo "N_SM=$n_sm N_ESTAB=$n_estab PROT=$prot"
if [ "$prot" -ge 1 ] && [ "$n_estab" -eq 1 ] && [ "$n_sm" -le 2 ]; then ok "H6/H7 reaper protect + single estab server-main"; else bad "H6/H7 prot=$prot sm=$n_sm estab=$n_estab"; fi

# H8 cron
f=/etc/cron.d/cursor-server-reaper
if [ ! -f "$f" ]; then bad "H8 cron missing"
else
  lines=$(wc -l < "$f")
  bytes=$(wc -c < "$f")
  tail -c 1 "$f" | od -An -t x1 | grep -q '0a' && nl=1 || nl=0
  grep -q 'cursor-server-reaper --apply' "$f" && apply=1 || apply=0
  echo "CRON lines=$lines bytes=$bytes nl=$nl apply=$apply"
  cat -A "$f"
  if [ "$lines" -ge 3 ] && [ "$lines" -le 8 ] && [ "$nl" -eq 1 ] && [ "$apply" -eq 1 ] && [ "$bytes" -lt 500 ]; then
    ok "H8 cron well-formed"
  else
    bad "H8 cron malformed"
  fi
fi

echo ""
echo "=== SERVER HARD: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
exit $?
