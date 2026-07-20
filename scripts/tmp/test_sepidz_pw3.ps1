$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pw = Get-SepidzSudoPassword
if ([string]::IsNullOrWhiteSpace($pw)) { Write-Host 'PW_TEST_RED empty'; exit 1 }
Write-Host ("OK load len={0}" -f $pw.Length)

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$lines = @(
  '#!/bin/bash',
  'set -e',
  ('PW=$(echo {0} | base64 -d)' -f $pwB64),
  'printf ''%s\n'' "$PW" | sudo -S -p '''' -v',
  'echo SUDO_AUTH_OK',
  'echo SUDO_UID=$(printf ''%s\n'' "$PW" | sudo -S -p '''' id -u)',
  'echo WHO=$(printf ''%s\n'' "$PW" | sudo -S -p '''' whoami)',
  'echo DONE'
)
[IO.File]::WriteAllBytes("$env:TEMP\t3.sh", [Text.Encoding]::UTF8.GetBytes((($lines -join "`n")+"`n")))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\t3.sh" 'sepidz@192.168.250.70:/tmp/t3.sh'
$out="$env:TEMP\t3.out"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no','sepidz@192.168.250.70','bash /tmp/t3.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(30000)) { Write-Host 'PW_TEST_RED timeout'; exit 1 }
$txt = (Get-Content $out -Raw -EA SilentlyContinue) + ''
Write-Host $txt
# version separate
$vout="$env:TEMP\tv.out"
$p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','sepidz@192.168.250.70',"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $vout -RedirectStandardError "$vout.err"
[void]$p2.WaitForExit(15000)
$ver = ((Get-Content $vout -Raw -EA SilentlyContinue)+'').Trim()
Write-Host "BUNDLE=$ver"

$ok = ($txt -match 'SUDO_AUTH_OK') -and ($txt -match 'SUDO_UID=0') -and ($txt -match 'WHO=root') -and ($txt -match 'DONE') -and ($ver -eq '20260718.1')
$credOk = (Select-String -Path "$root\publish\Get-DeployCredentials.ps1" -Pattern "return 'sepidz@Admin'" -Quiet)
$depOk  = (Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'sepidz@Admin' -Quiet)
Write-Host ("hardcode_cred={0} hardcode_deploy={1}" -f $credOk, $depOk)
if ($ok -and $credOk -and $depOk) { Write-Host 'PW_TEST_GREEN'; exit 0 }
Write-Host 'PW_TEST_RED'; exit 1
