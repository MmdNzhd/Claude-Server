$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }

Write-Host '======== STATIC DEEP (REPO) ========'
# Win vs Mac parity of heal wiring
$ps1 = Get-Content "$root\scripts\client\git-mode.ps1" -Raw
$sh  = Get-Content "$root\scripts\client\git-mode.sh" -Raw
$pub = Get-Content "$root\publish\publish.ps1" -Raw
@(
  @{N='Win push self-heal+automount'; Ok=($ps1 -match 'claude-self-heal\.sh' -and $ps1 -match 'claude-automount\.sh')},
  @{N='Win conf-push heal'; Ok=($ps1 -match 'claude-self-heal --quiet')},
  @{N='Win CRLF strip after push'; Ok=($ps1 -match "sed -i 's/\\r\`$//'")},
  @{N='Win LAPTOP_OS=windows'; Ok=($ps1 -match 'LAPTOP_OS=windows')},
  @{N='Mac push self-heal+automount'; Ok=($sh -match 'claude-self-heal\.sh' -and $sh -match 'claude-automount\.sh')},
  @{N='Mac conf-push heal'; Ok=($sh -match 'claude-self-heal --quiet')},
  @{N='Mac CRLF strip after push'; Ok=($sh -match 'sed -i')},
  @{N='Mac LAPTOP_OS var'; Ok=($sh -match 'GIT_MODE_LAPTOP_OS')},
  @{N='publish mac heal+auto'; Ok=($pub -match 'mac\\claude-self-heal\.sh' -and $pub -match 'mac\\claude-automount\.sh')},
  @{N='publish win heal+auto'; Ok=($pub -match 'windows\\claude-self-heal\.sh' -and $pub -match 'windows\\claude-automount\.sh')},
  @{N='Mac connect sources git-mode'; Ok=((Get-Content "$root\scripts\client\mac\connect.sh" -Raw) -match 'git-mode.sh')},
  @{N='Win connect sources git-mode'; Ok=((Get-Content "$root\scripts\client\windows\connect.ps1" -Raw) -match 'git-mode.ps1')},
  @{N='heal no mountpoint hang'; Ok=((Get-Content "$root\scripts\server\claude-self-heal.sh" -Raw) -match 'Never use mountpoint')},
  @{N='automount heal tunnel-down'; Ok=((Get-Content "$root\scripts\server\claude-automount.sh" -Raw) -match 'Still self-heal')}
) | ForEach-Object { if ($_.Ok) { OK $_.N } else { FAIL $_.N } }

Write-Host '======== STATIC TESTS ========'
foreach ($t in @('scripts\client\tests\test-connect-pipeline.ps1','scripts\client\tests\test-git-mode-deep.ps1')) {
  Write-Host "RUN $t"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $t) | Out-Null
  if ($LASTEXITCODE -ne 0) { FAIL "$t exit=$LASTEXITCODE" } else { OK $t }
}

Write-Host '======== LIVE DEEP PLUS ========'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q "$root\scripts\tmp\deep_plus.py" 'sepidz@192.168.250.70:/tmp/deep_plus.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_plus.py' + $nl + 'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\dp.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\dp.sh" 'sepidz@192.168.250.70:/tmp/dp.sh'
$out = "$env:TEMP\dp_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/dp.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(360000)) { try{$p.Kill()}catch{}; FAIL 'live TIMEOUT' }
else {
  $txt = Get-Content $out -Raw
  Write-Host $txt
  if ($txt -match 'DEEP_PLUS_GREEN' -and $txt -match 'fail=0') { OK 'live deep-plus' }
  else { FAIL 'live deep-plus red' }
}

Write-Host '======== SMART VERSION ========'
$sout = "$env:TEMP\smartv.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $sout -RedirectStandardError "$sout.err"
[void]$p2.WaitForExit(12000)
$sv = if (Test-Path $sout) { (Get-Content $sout -Raw).Trim() } else { '' }
if ($sv -eq '20260717.22') { OK "smart=$sv frozen-until-tonight" } else { Write-Host "WARN smart=$sv" }

Write-Host '======== RESULT ========'
Write-Host "local_fail=$fail"
if ($fail -ne 0) { Write-Host 'ALL_DEEP_PLUS_RED'; exit 1 }
Write-Host 'ALL_DEEP_PLUS_GREEN'
exit 0
