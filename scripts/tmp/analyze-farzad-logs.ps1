$ErrorActionPreference = 'Continue'
# Pull key lines + full log to laptop temp for analysis
$remote = @'
echo sepidz@Admin | sudo -S -p '' bash -lc '
LOG=/home/farzadb/.claude/logs/connect-20260719.log
echo "=== META ==="
wc -l "$LOG"; ls -lah "$LOG"; date -Is
echo "=== VERSION HITS ==="
grep -nE "connect-version|CLIENT_VERSION|version=|v2026|UPDATE|auto-update|AutoUpdate|bundle" "$LOG" | tail -80
echo "=== SESSION MARKERS ==="
grep -nE "SESSION_LOOP begin|SESSION_OPEN|SESSION_CLOSE|CONNECT_START|CONNECT_END|ACTIVE_MOUNT|tunnel_down|CLEAR_MOUNT|RECOVERY|ENSURE|ORPHAN|soft_fail|FINALLY_KEEP|RECOVERY_SKIP|EditorSeen|editor open|VERDICT|Connection failed|EIO|SSHFS" "$LOG" | tail -120
echo "=== ERROR/WARN last 80 ==="
grep -nE "\[(ERROR|WARN)\]" "$LOG" | tail -80
echo "=== LAST 100 LINES ==="
tail -n 100 "$LOG"
'
'@
ssh -n -o BatchMode=yes -o ConnectTimeout=20 -o IdentityAgent=none sepidz@192.168.250.70 $remote
