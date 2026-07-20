$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$sudoPw = Get-SepidzSudoPassword
$repo = 'D:\Smart\Claude-Code-Server'
$files = @(
  'scripts\server\claude-automount.sh',
  'scripts\server\claude-self-heal.sh',
  'scripts\server\claude-watchdog.sh',
  'scripts\server\claude-mount.sh'
)
# syntax check via ssh after upload is safer; strip BOM locally first
foreach ($rel in $files) {
  $p = Join-Path $repo $rel
  $b = [IO.File]::ReadAllBytes($p)
  if ($b.Length -ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF) {
    [IO.File]::WriteAllBytes($p, $b[3..($b.Length-1)])
    Write-Host "stripped BOM $rel"
  }
  $t = [IO.File]::ReadAllText($p) -replace "`r`n","`n" -replace "`r","`n"
  [IO.File]::WriteAllBytes($p, [Text.Encoding]::UTF8.GetBytes($t))
}
Write-Host '=== upload ==='
ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=15 sepidz@192.168.250.70 "mkdir -p ~/claude-edge-deploy"
foreach ($rel in $files) {
  $name = Split-Path $rel -Leaf
  scp -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=30 -q (Join-Path $repo $rel) "sepidz@192.168.250.70:~/claude-edge-deploy/$name"
  Write-Host "uploaded $name"
}
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sudoPw))
$remote = @'
#!/bin/bash
set -euo pipefail
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
cd "$HOME/claude-edge-deploy"
sed -i 's/\r$//' *.sh
for f in claude-automount.sh claude-self-heal.sh claude-watchdog.sh claude-mount.sh; do
  bash -n "$f" || { echo "SYNTAX_FAIL $f"; exit 1; }
done
echo SYNTAX_OK
S bash -c '
set -euo pipefail
cd /home/sepidz/claude-edge-deploy
install -m 755 claude-automount.sh /usr/local/bin/claude-automount
install -m 755 claude-self-heal.sh /usr/local/bin/claude-self-heal
install -m 755 claude-watchdog.sh /usr/local/bin/claude-watchdog
install -m 755 claude-mount.sh /usr/local/lib/claude-mount
ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount
# markers
grep -q VSCODE_RESOLVING_ENVIRONMENT /usr/local/bin/claude-automount
grep -q claude-last-active-mount /usr/local/bin/claude-automount
grep -q _heal_active_remount /usr/local/bin/claude-self-heal
grep -q _heal_connect_log_bufs /usr/local/bin/claude-self-heal
grep -q need_remount /usr/local/bin/claude-watchdog
echo MARKERS_OK
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  [ "$u" = lost+found ] && continue
  mkdir -p "$home/.local/bin" "$home/.cache"
  for b in claude-automount claude-self-heal claude-watchdog; do
    install -m 755 /usr/local/bin/$b "$home/.local/bin/$b"
  done
  install -m 755 /usr/local/lib/claude-mount "$home/.local/bin/claude-mount"
  chown -R "$u:$u" "$home/.local/bin" "$home/.cache" 2>/dev/null || true
  br="$home/.bashrc"
  if [ -f "$br" ] && grep -q claude-automount "$br"; then
    if ! grep -qE "timeout[[:space:]]+10[[:space:]].*claude-automount" "$br"; then
      sed -i -E "s@(\\\$HOME/\.local/bin/claude-automount|/usr/local/bin/claude-automount)[[:space:]]+2>/dev/null@timeout 10 \\1 2>/dev/null@g" "$br"
      chown "$u:$u" "$br"
    fi
  fi
  # restart watchdog: kill old lock/process
  rm -f /tmp/claude-watchdog-$u.pid
  pkill -u "$u" -f "/usr/local/bin/claude-watchdog|/home/$u/.local/bin/claude-watchdog" 2>/dev/null || true
done
# system cron: self-heal all users every 5 minutes
cat >/etc/cron.d/claude-self-heal <<CRON
*/5 * * * * root for u in \$(ls /home); do id "\$u" >/dev/null 2>&1 || continue; [ -f /home/\$u/.claude-connect.conf ] || continue; sudo -u "\$u" -H /usr/local/bin/claude-self-heal --quiet >/dev/null 2>&1 || true; done
CRON
chmod 644 /etc/cron.d/claude-self-heal
echo CRON_OK
'

echo === HEAL+REMOUNT ALL ===
S bash -c '
for home in /home/*/; do
  u=$(basename "$home")
  id "$u" >/dev/null 2>&1 || continue
  [ -f "$home/.claude-connect.conf" ] || continue
  echo "==== $u ===="
  sudo -u "$u" -H /usr/local/bin/claude-self-heal 2>&1 | tail -15 || true
  # start watchdog if tunnel up
  port=$(grep ^TUNNEL_PORT= "$home/.claude-connect.conf" | cut -d= -f2 | tr -d "\r")
  if [ -n "$port" ] && timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    sudo -u "$u" -H bash -c "nohup /usr/local/bin/claude-watchdog >/dev/null 2>&1 &" || true
    echo watchdog_started
  fi
done
'

echo === FINAL MATRIX ===
S bash -c '
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf" | cut -d= -f2 | tr -d "\r")
  active=$(grep ^ACTIVE_MOUNT= "$conf" | cut -d= -f2 | tr -d "\r")
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then t=UP; else t=DOWN; fi
  mounts=""
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    n=$(basename "$m")
    if grep -q " $m " /proc/mounts; then
      if timeout 2 ls "$m" >/dev/null 2>&1; then mounts="$mounts $n:OK"; else mounts="$mounts $n:ZOMBIE"; fi
    fi
  done
  wd=$(pgrep -u $u -f claude-watchdog >/dev/null && echo WD:yes || echo WD:no)
  echo "$u tunnel=$t port=$port active=${active:-(empty)} mounts=${mounts:-(none)} $wd"
done
# shell env speed
/usr/bin/time -f "shell_env_skip=%e" timeout 15 sudo -u hosseinb -H env VSCODE_RESOLVING_ENVIRONMENT=1 bash -ilc "echo OK" >/dev/null 2>/tmp/t1 || true
cat /tmp/t1 | tail -1
'
'@
$remote = $remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'deploy-edges.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/de.sh && bash /tmp/de.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(360000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e.Trim()){Write-Host ERR:; Write-Host $e} }
if($p.ExitCode -ne 0){ throw "exit $($p.ExitCode)" }
