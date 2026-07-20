$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }

Write-Host '======== STATIC (repo Win/Mac + new patches) ========'
$ps1 = Get-Content "$root\scripts\client\git-mode.ps1" -Raw
$sh  = Get-Content "$root\scripts\client\git-mode.sh" -Raw
$pub = Get-Content "$root\publish\publish.ps1" -Raw
$heal = Get-Content "$root\scripts\server\claude-self-heal.sh" -Raw
$setup = Get-Content "$root\scripts\server\laptop-exec-setup.sh" -Raw
$dep = Get-Content "$root\scripts\server\commands\deploy-laptop-exec.sh" -Raw
@(
  @{N='heal missing-bins'; Ok=($heal -match '_heal_missing_user_bins')},
  @{N='setup self-install'; Ok=($setup -match 'Keep setup itself in PATH')},
  @{N='deploy user setup+auto'; Ok=($dep -match 'laptop-exec-setup' -and $dep -match 'claude-automount')},
  @{N='Win conf-push heal'; Ok=($ps1 -match 'claude-self-heal --quiet')},
  @{N='Mac conf-push heal'; Ok=($sh -match 'claude-self-heal --quiet')},
  @{N='publish ships heal both OS'; Ok=($pub -match 'mac\\claude-self-heal\.sh' -and $pub -match 'windows\\claude-self-heal\.sh')},
  @{N='heal no mountpoint'; Ok=($heal -match 'Never use mountpoint')}
) | ForEach-Object { if ($_.Ok) { OK $_.N } else { FAIL $_.N } }

Write-Host '======== LIVE DEEP ULTRA ========'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q "$root\scripts\tmp\deep_ultra.py" 'sepidz@192.168.250.70:/tmp/deep_ultra.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_ultra.py' + $nl + 'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\du.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\du.sh" 'sepidz@192.168.250.70:/tmp/du.sh'
$out = "$env:TEMP\du_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/du.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(420000)) { try{$p.Kill()}catch{}; FAIL 'live TIMEOUT' }
else {
  $txt = Get-Content $out -Raw
  Write-Host $txt
  if ($txt -match 'DEEP_ULTRA_GREEN' -and $txt -match 'fail=0') { OK 'live deep-ultra' }
  else { FAIL 'live deep-ultra red' }
}

Write-Host '======== SMART VERSION ========'
$sout = "$env:TEMP\smartv2.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $sout -RedirectStandardError "$sout.err"
[void]$p2.WaitForExit(12000)
$sv = if (Test-Path $sout) { (Get-Content $sout -Raw).Trim() } else { '' }
if ($sv -eq '20260717.22') { OK "smart=$sv frozen-until-tonight" } else { Write-Host "WARN smart=$sv" }

Write-Host '======== RESULT ========'
Write-Host "local_fail=$fail"
if ($fail -ne 0) { Write-Host 'ALL_DEEP_ULTRA_RED'; exit 1 }
Write-Host 'ALL_DEEP_ULTRA_GREEN'
exit 0
