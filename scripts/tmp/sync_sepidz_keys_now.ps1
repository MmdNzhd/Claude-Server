$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
ak=/home/sepidz/.ssh/authorized_keys
tmp=$(mktemp)
[ -f "$ak" ] && cat "$ak" >"$tmp" || : >"$tmp"
before=$(wc -l <"$tmp" | tr -d " ")
for d in /home/*; do
  u=$(basename "$d")
  case "$u" in sepidz|root) continue ;; esac
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
after=$(wc -l <"$ak" | tr -d " ")
rm -f "$tmp"
echo "sepidz keys: $before -> $after"
ssh-keygen -lf "$ak"
# verify farzad key present
fk=$(awk "{print \$2}" /home/farzadb/.ssh/authorized_keys | head -1)
if grep -q "$fk" "$ak"; then echo FARZAD_IN_SEPIDZ=YES; else echo FARZAD_IN_SEPIDZ=NO; fi
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'sk.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
if (Test-Path ($out+'.err')) { Get-Content ($out+'.err') -Raw }
