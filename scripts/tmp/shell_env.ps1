$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
for u in farzadb hosseinb; do
  echo "=== $u shell rc ==="
  for f in .bashrc .profile .bash_profile .zshrc .bash_login; do
    if S test -f /home/$u/$f; then
      echo "-- $f --"
      S wc -l /home/$u/$f
      S grep -nEi 'mount|sshfs|claude|cursor|sleep|wait|ssh |source |eval|nvm|conda|oh-my' /home/$u/$f 2>/dev/null | head -40
    fi
  done
  echo "=== $u time bash -lc ==="
  S timeout 15 bash -lc "echo OK_$u; echo HOME=\$HOME" 2>&1 || echo "TIMEOUT_OR_FAIL_$u"
  echo
done
echo === HOSSEINB mounts status ===
S grep hosseinb /proc/mounts || echo no_mounts
S ls -lah /home/hosseinb/mounts 2>&1 | head -20
timeout 3 S ls /home/hosseinb/mounts/backend 2>&1 | head -5 || echo backend_ls_hang
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'shell-env.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/se.sh && bash /tmp/se.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(90000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
