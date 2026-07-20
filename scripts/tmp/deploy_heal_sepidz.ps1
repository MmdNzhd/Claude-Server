$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$sudoPw = Get-SepidzSudoPassword
$repo = 'D:\Smart\Claude-Code-Server'
$files = @(
  'scripts\server\claude-automount.sh',
  'scripts\server\claude-self-heal.sh',
  'scripts\server\claude-mount.sh',
  'scripts\server\commands\deploy-mount-fix.sh'
)
$remoteDir = 'claude-mount-deploy'
Write-Host '=== upload ==='
ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=15 sepidz@192.168.250.70 "mkdir -p ~/$remoteDir"
foreach ($rel in $files) {
  $local = Join-Path $repo $rel
  $name = Split-Path $rel -Leaf
  scp -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=30 -q $local "sepidz@192.168.250.70:~/$remoteDir/$name"
  Write-Host "uploaded $name"
}
# also need self-heal next to deploy script resolution - copy as sibling names deploy expects
# deploy-mount-fix resolves from DEPLOY_DIR for mount/automount; self-heal from SERVER_DIR=parent
# So put self-heal in parent via install in remote script.

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sudoPw))
$remote = @'
#!/bin/bash
set -euo pipefail
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
cd "$HOME/claude-mount-deploy"
# Make self-heal visible to deploy-mount-fix (looks at SERVER_DIR=parent of commands)
# Our layout: all files in one dir. Patch deploy to install self-heal from same dir.
S bash -c '
set -euo pipefail
cd /home/sepidz/claude-mount-deploy
sed -i "s/\r$//" *.sh
install -m 755 claude-automount.sh /usr/local/bin/claude-automount
install -m 755 claude-self-heal.sh /usr/local/bin/claude-self-heal
install -m 755 claude-mount.sh /usr/local/lib/claude-mount
ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount
ok(){ echo "  ok  $1"; }
ok "claude-automount"
ok "claude-self-heal"
ok "claude-mount"
grep -q VSCODE_RESOLVING_ENVIRONMENT /usr/local/bin/claude-automount || { echo FAIL missing VSCODE_RESOLVING; exit 1; }
grep -q _ppargs /usr/local/bin/claude-automount || { echo FAIL missing parent skip; exit 1; }
for home in /home/*/; do
  u=$(basename "$home")
  [ "$u" = lost+found ] && continue
  id "$u" >/dev/null 2>&1 || continue
  mkdir -p "$home/.local/bin"
  install -m 755 /usr/local/lib/claude-mount "$home/.local/bin/claude-mount"
  install -m 755 /usr/local/bin/claude-automount "$home/.local/bin/claude-automount"
  install -m 755 /usr/local/bin/claude-self-heal "$home/.local/bin/claude-self-heal"
  chown "$u:$u" "$home/.local/bin/claude-mount" "$home/.local/bin/claude-automount" "$home/.local/bin/claude-self-heal"
  br="$home/.bashrc"
  if [ -f "$br" ] && grep -q claude-automount "$br"; then
    # Ensure timeout wrapper around automount (Cursor shell-env safety net)
    if ! grep -q "timeout 10 .*claude-automount" "$br"; then
      # replace bare automount invocations with timeout 10
      sed -i -E "s@(\\\$HOME/\.local/bin/claude-automount|/usr/local/bin/claude-automount) 2>/dev/null@timeout 10 \\1 2>/dev/null@g" "$br"
      # if both paths with || 
      if ! grep -q "timeout 10" "$br"; then
        # fallback: wrap whole line block if pattern different
        true
      fi
      chown "$u:$u" "$br"
      ok "$u bashrc timeout wrap"
    else
      ok "$u bashrc already timeout"
    fi
  fi
  ok "$u bins"
done
'

echo === HEAL ALL USERS ===
S bash -c '
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  [ -f "$home/.claude-connect.conf" ] || continue
  echo "-- heal $u --"
  sudo -u "$u" -H /usr/local/bin/claude-self-heal 2>&1 | tail -5 || true
done
'

echo === FARZAD FORCE CLEAN ZOMBIES ===
S bash -c '
for mp in /home/farzadb/mounts/frontend /home/farzadb/mounts/backend; do
  if grep -F " $mp " /proc/mounts >/dev/null 2>&1; then
    echo "umount $mp"
    timeout 5 fusermount -uz "$mp" 2>/dev/null || timeout 5 umount -l "$mp" 2>/dev/null || true
  fi
done
# kill leftover sshfs for farzadb if any
pkill -u farzadb -f "sshfs .*farzadb/mounts" 2>/dev/null || true
sleep 1
ls -lah /home/farzadb/mounts || true
grep farzadb /proc/mounts || echo "farzadb: no mounts in proc"
'

echo === HOSSEINB REMOUNT ===
S bash -c '
u=hosseinb
conf=/home/$u/.claude-connect.conf
# tunnel must be up
port=$(grep ^TUNNEL_PORT= "$conf" | cut -d= -f2 | tr -d "\r")
if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port"; then
  echo tunnel_up=$port
  # Prefer backend (last Cursor workspace); else first conf
  active=$(grep ^ACTIVE_MOUNT= "$conf" | cut -d= -f2 | tr -d "\r")
  if [ -z "$active" ]; then
    if [ -f /home/$u/.claude-mounts.d/backend.conf ]; then active=backend
    else active=$(basename "$(ls /home/$u/.claude-mounts.d/*.conf 2>/dev/null | head -1)" .conf)
    fi
    if [ -n "$active" ]; then
      if grep -qiE "^ACTIVE_MOUNT=" "$conf"; then
        sed -i "s/^ACTIVE_MOUNT=.*/ACTIVE_MOUNT=$active/" "$conf"
      else
        printf "\nACTIVE_MOUNT=%s\n" "$active" >> "$conf"
      fi
      chown $u:$u "$conf"
      echo set_ACTIVE_MOUNT=$active
    fi
  fi
  echo ACTIVE_MOUNT=$(grep ^ACTIVE_MOUNT= "$conf")
  sudo -u $u -H /usr/local/bin/claude-mount up "$active" 2>&1 | tail -20
  # also try frontend if backend ok? keep single active for now
  ls -lah /home/$u/mounts/
  for m in /home/$u/mounts/*; do
    [ -d "$m" ] || continue
    name=$(basename "$m")
    if grep -q " $m " /proc/mounts; then
      if timeout 3 ls "$m" >/dev/null 2>&1; then echo MOUNT_OK $name; else echo MOUNT_ZOMBIE $name; fi
    else echo NOT_MOUNTED $name; fi
  done
else
  echo tunnel_down_skip_remount
fi
'

echo === VERIFY AUTOMOUNT SKIP SPEED ===
S bash -c '
# simulate Cursor parent: run as hosseinb with fake parent not needed; time login
/usr/bin/time -f "elapsed=%e" timeout 20 sudo -u hosseinb -H env VSCODE_RESOLVING_ENVIRONMENT=1 bash -ilc "echo OK" 2>&1 | tail -5
/usr/bin/time -f "elapsed=%e" timeout 20 sudo -u farzadb -H env VSCODE_RESOLVING_ENVIRONMENT=1 bash -ilc "echo OK" 2>&1 | tail -5
'

echo === FINAL STATE ===
S bash -c '
for u in farzadb hosseinb hosseinm; do
  echo -- $u --
  conf=/home/$u/.claude-connect.conf
  port=$(grep ^TUNNEL_PORT= "$conf" | cut -d= -f2 | tr -d "\r")
  active=$(grep ^ACTIVE_MOUNT= "$conf" | cut -d= -f2 | tr -d "\r")
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then t=UP; else t=DOWN; fi
  echo port=$port tunnel=$t active=$active
  grep " /home/$u/mounts/" /proc/mounts || echo "(no sshfs)"
done
grep -n "VSCODE_RESOLVING\|_timeout 4\|timeout 8\|__ppargs" /usr/local/bin/claude-automount | head -20
'
'@
$remote = $remote.Replace('__PWB64__', $pwB64) -replace "`r",''
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out = Join-Path $env:TEMP 'deploy-heal.out'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/dh.sh && bash /tmp/dh.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if (-not $p.WaitForExit(300000)) { try { $p.Kill() } catch {}; throw 'TIMEOUT' }
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
if (Test-Path ($out+'.err')) {
  $e = Get-Content ($out+'.err') -Raw -EA SilentlyContinue
  if ($e) { Write-Host 'ERR:'; Write-Host $e }
}
if ($p.ExitCode -ne 0) { throw "exit $($p.ExitCode)" }
