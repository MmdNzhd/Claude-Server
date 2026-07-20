$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$lines = @(
  '#!/bin/bash','set -e',
  ('PW=$(echo {0} | base64 -d)' -f $pwB64),
  'printf ''%s\n'' "$PW" | sudo -S -p '''' -v',
  'echo SUDO_AUTH_OK',
  'U=$(printf ''%s\n'' "$PW" | sudo -S -p '''' id -u)',
  'echo SUDO_UID=$U',
  'V=$(printf ''%s\n'' "$PW" | sudo -S -p '''' tr -d ''\r\n'' < /usr/local/share/claude-client/connect-version.txt)',
  'echo BUNDLE=$V',
  'echo DONE'
)
[IO.File]::WriteAllBytes("$env:TEMP\t2.sh", [Text.Encoding]::UTF8.GetBytes((($lines -join "`n")+"`n")))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\t2.sh" 'sepidz@192.168.250.70:/tmp/t2.sh'
$out="$env:TEMP\t2.out"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no','sepidz@192.168.250.70','bash /tmp/t2.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
[void]$p.WaitForExit(45000)
$txt = (Get-Content $out -Raw -EA SilentlyContinue) + ''
Write-Host $txt
$ok = ($txt -match 'SUDO_AUTH_OK') -and ($txt -match 'SUDO_UID=0') -and ($txt -match 'BUNDLE=20260718\.1') -and ($txt -match 'DONE')
if ($ok) { Write-Host 'PW_TEST_GREEN'; exit 0 }
Write-Host 'PW_TEST_RED'; exit 1
