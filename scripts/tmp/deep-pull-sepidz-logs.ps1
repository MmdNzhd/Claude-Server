$ErrorActionPreference='Continue'
Write-Output '=== VERSIONS ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt; hostname"
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt; hostname"

$remote = @'
echo sepidz@Admin | sudo -S -p '' bash -s <<'INNER'
for u in alit aminb designer farzadb hosseinb hosseinm nimaz sepidz smart zahrak; do
  f=/home/$u/.claude/logs/connect-20260719.log
  if [ -f "$f" ]; then
    sz=$(wc -c <"$f" | tr -d ' ')
    ln=$(wc -l <"$f" | tr -d ' ')
    mt=$(stat -c %y "$f" | cut -d. -f1)
    conf=$(grep -E '^(LAPTOP_USER|TUNNEL_PORT|GIT_MODE|ACTIVE_MOUNT)=' /home/$u/.claude-connect.conf 2>/dev/null | paste -sd';' -)
    echo "USER=$u SIZE=$sz LINES=$ln MTIME=$mt CONF=$conf"
  else
    echo "USER=$u NO_LOG"
  fi
done
cp -f /home/farzadb/.claude/logs/connect-20260719.log /tmp/farzad-connect-20260719.log 2>/dev/null || true
chmod 644 /tmp/farzad-connect-20260719.log 2>/dev/null || true
chown sepidz:sepidz /tmp/farzad-connect-20260719.log 2>/dev/null || true
wc -c /tmp/farzad-connect-20260719.log
INNER
'@
Write-Output '=== USER LOG INDEX ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=20 -o IdentityAgent=none sepidz@192.168.250.70 $remote
Write-Output '=== SCP FARZAD ==='
scp -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70:/tmp/farzad-connect-20260719.log D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log
Write-Output ("saved=" + (Get-Item D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log).Length)
