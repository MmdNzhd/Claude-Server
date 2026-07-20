$ErrorActionPreference='Continue'
. publish\sepidz-deploy.local.ps1
$pw = [string]$SepidzSudoPassword
if(-not $pw){ Write-Host 'NO_PW'; exit 2 }

$bash = @'
set +e
echo "==== META $(hostname) $(date -Is) ===="
echo "---- reverse tunnels listening ----"
ss -ltn | grep -E '2100[0-9]' || echo '(none)'
echo "---- sshfs mounts ----"
mount | grep -E 'fuse.sshfs|sshfs' || echo '(no sshfs)'
echo "---- load ----"
uptime

echo "==== CONNECT LOG FILES ===="
ls -lt /home/*/.claude/logs/connect-*.log 2>/dev/null

for f in /home/*/.claude/logs/connect-20260719.log; do
  [ -f "$f" ] || continue
  u=$(echo "$f" | cut -d/ -f3)
  echo ""
  echo "######## USER=$u FILE=$f bytes=$(wc -c <"$f") ########"
  echo "-- session starts --"
  grep -E 'session start v' "$f" | tail -8
  echo "-- tunnel recover / refused / fail counts --"
  echo -n "recover=$(grep -c 'TUNNEL: recovering' "$f" 2>/dev/null || echo 0) "
  echo -n "refused=$(grep -c 'Connection refused' "$f" 2>/dev/null || echo 0) "
  echo -n "ERROR=$(grep -c '\[ERROR\]' "$f" 2>/dev/null || echo 0) "
  echo -n "STEP_fail=$(grep -c 'STEP end:.*failed' "$f" 2>/dev/null || echo 0) "
  echo -n "mount_ok=$(grep -c 'STEP end: Mounting files ok' "$f" 2>/dev/null || echo 0) "
  echo "session_end=$(grep -c 'session end' "$f" 2>/dev/null || echo 0)"
  echo "-- last 5 refused --"
  grep 'Connection refused' "$f" | tail -5
  echo "-- last 3 recovers --"
  grep 'TUNNEL: recovering\|ENSURE_TUNNEL ok\|ENSURE_TUNNEL spawned\|session end\|Opening Cursor\|MOUNT:' "$f" | tail -15
  echo "-- ERROR lines --"
  grep '\[ERROR\]\|StepFail\|STEP end:.*failed' "$f" | tail -10
done

echo ""
echo "==== FARZADB FULL STORY ==== "
f=/home/farzadb/.claude/logs/connect-20260719.log
grep -E 'session start|STEP |TUNNEL|MOUNT|LAUNCH|AUTH|session end|ERROR|failed|refused' "$f" | head -80

echo ""
echo "==== ZAHRAK FULL STORY ===="
f=/home/zahrak/.claude/logs/connect-20260719.log
grep -E 'session start|STEP |TUNNEL|MOUNT|LAUNCH|AUTH|session end|ERROR|failed|refused' "$f" | head -80

echo ""
echo "==== AMINB last session block ===="
f=/home/aminb/.claude/logs/connect-20260719.log
# last session start line number-ish via tac
grep -E 'session start v|TUNNEL: recovering|ENSURE_TUNNEL ok|STEP end:|session end|Opening Cursor|MOUNT:|Connection refused' "$f" | tail -40

echo ""
echo "==== HOSSEINB last session block ===="
f=/home/hosseinb/.claude/logs/connect-20260719.log
grep -E 'session start v|TUNNEL: recovering|ENSURE_TUNNEL ok|STEP end:|session end|Opening Cursor|MOUNT:|Connection refused' "$f" | tail -40

echo ""
echo "==== CURSOR remoteagent disconnects today ===="
for u in farzadb aminb hosseinb zahrak smart; do
  d=$(ls -td /home/$u/.cursor-server/data/logs/* 2>/dev/null | head -1)
  [ -n "$d" ] || { echo "$u: no cursor logs"; continue; }
  echo "-- $u $d --"
  grep -hE 'New connection|disconnected|Error|ECONN|EIO|timeout|refused' "$d"/remoteagent.log 2>/dev/null | tail -12
done

echo ""
echo "==== AUTH summary (failed vs accepted counts today) ===="
grep -c 'Failed password' /var/log/auth.log 2>/dev/null | awk '{print "Failed_password="$1}'
grep -c 'Accepted publickey' /var/log/auth.log 2>/dev/null | awk '{print "Accepted_pubkey_all="$1}'
for u in farzadb aminb hosseinb zahrak; do
  a=$(grep -c "Accepted publickey for $u" /var/log/auth.log 2>/dev/null || echo 0)
  echo "Accepted_$u=$a"
done
echo DONE
'@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
$pwEsc = $pw.Replace("'","'""'""'")
$remote = "printf '%s\n' '$pwEsc' | sudo -S -p '' bash -c 'echo $b64 | base64 -d | bash'"
$o="$env:TEMP\sepidz-full.out"; $e="$env:TEMP\sepidz-full.err"
Remove-Item $o,$e -Force -EA SilentlyContinue
$p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=12','sepidz@192.168.250.70',$remote) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if(-not $p.WaitForExit(120000)){ try{$p.Kill()}catch{}; Write-Host TIMEOUT }
else { Write-Host "exit=$($p.ExitCode)" }
Get-Content $o
