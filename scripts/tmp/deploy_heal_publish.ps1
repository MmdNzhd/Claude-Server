$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))

# Upload patched server command scripts
$files=@(
  @{ Local='D:\Smart\Claude-Code-Server\scripts\server\commands\add-user.sh'; Remote='/tmp/add-user.sh' },
  @{ Local='D:\Smart\Claude-Code-Server\scripts\server\commands\install-client-bundle.sh'; Remote='/tmp/install-client-bundle.sh' },
  @{ Local='D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-client-bundle.sh'; Remote='/tmp/deploy-client-bundle.sh' }
)
foreach($f in $files){
  & scp -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=15 $f.Local ("sepidz@192.168.250.70:"+$f.Remote)
  if($LASTEXITCODE -ne 0){ throw "scp failed $($f.Local)" }
  Write-Host "uploaded $($f.Remote)"
}

$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
set -e
for s in add-user install-client-bundle deploy-client-bundle; do
  src=/tmp/$s.sh
  # find install location
  for dest in /usr/local/lib/claude-server/commands/$s.sh /usr/local/share/claude-server/commands/$s.sh /opt/claude-server/commands/$s.sh; do
    if [ -f "$dest" ]; then
      install -m 755 "$src" "$dest"
      echo "installed $dest"
      break
    fi
  done
  # also via claude-server path discovery
  if [ -L /usr/local/bin/claude-server ] || [ -f /usr/local/bin/claude-server ]; then
    base=$(dirname "$(readlink -f /usr/local/bin/claude-server 2>/dev/null || echo /usr/local/bin/claude-server)")
    for cand in "$base/commands/$s.sh" "$base/../commands/$s.sh"; do
      if [ -f "$cand" ]; then install -m 755 "$src" "$cand"; echo "installed $cand"; fi
    done
  fi
done
# locate commands dir
find /usr/local -name "add-user.sh" 2>/dev/null | head -10
# heal all users
for u in $(ls /home); do
  id "$u" >/dev/null 2>&1 || continue
  [ -f /home/$u/.claude-connect.conf ] || continue
  echo "HEAL $u"
  sudo -u "$u" -H /usr/local/bin/claude-self-heal --quiet 2>&1 | tail -3 || true
done
# ensure bashrc timeouts for all
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak; do
  f=/home/$u/.bashrc
  [ -f "$f" ] || continue
  if grep -q claude-automount "$f" && ! grep -q "timeout 10" "$f"; then
    sed -i "s|\$HOME/.local/bin/claude-automount|timeout 10 \"\$HOME/.local/bin/claude-automount\"|g; s|/usr/local/bin/claude-automount|timeout 10 /usr/local/bin/claude-automount|g" "$f"
    echo "BASHRC_TIMEOUT_FIXED $u"
  else
    echo "BASHRC_OK $u"
  fi
done
# re-sync keys
ak=/home/sepidz/.ssh/authorized_keys
tmp=$(mktemp)
[ -f "$ak" ] && cat "$ak" >"$tmp" || : >"$tmp"
for d in /home/*; do
  u=$(basename "$d"); case "$u" in sepidz|root) continue ;; esac
  [ -f "$d/.ssh/authorized_keys" ] || continue
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ""|\#*) continue ;; ssh-*|ecdsa-*|sk-*) ;; *) continue ;; esac
    key=$(printf "%s\n" "$line" | awk "{print \$2}")
    [ -n "$key" ] || continue
    if ! awk -v k="$key" "\$2==k {found=1} END{exit !found}" "$tmp" 2>/dev/null; then
      printf "%s\n" "$line" >>"$tmp"
    fi
  done <"$d/.ssh/authorized_keys"
done
install -o sepidz -g sepidz -m 600 "$tmp" "$ak"
rm -f "$tmp"
echo "KEYS=$(wc -l <"$ak" | tr -d " ")"
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'dh.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=20','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(180000)
Get-Content $out -Raw
if((Test-Path ($out+'.err')) -and (Get-Item ($out+'.err')).Length -gt 0){ Write-Host 'ERR:'; Get-Content ($out+'.err') -Raw }
