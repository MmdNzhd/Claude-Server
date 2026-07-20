$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }

Write-Host '======== LOCAL HARDEN ========'
@(
  @{N='deploy base64'; Ok=(Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'base64, non-interactive' -Quiet)},
  @{N='deploy no hang'; Ok=(-not (Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern '\$SudoPassword \| & ssh' -Quiet))},
  @{N='git user policy'; Ok=(Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern 'Only remote User settings' -Quiet)},
  @{N='update msg'; Ok=(Select-String -Path "$root\scripts\client\windows\connect-update.ps1" -Pattern 'Client up to date' -Quiet)},
  @{N='dle crlf'; Ok=(Select-String -Path "$root\scripts\server\commands\deploy-laptop-exec.sh" -Pattern 'sed -i' -Quiet)},
  @{N='sudoers sepidz'; Ok=(Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:sepidz' -Quiet)}
) | ForEach-Object { if ($_.Ok) { OK $_.N } else { FAIL $_.N } }

$repo = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
if ($repo -eq '20260717.33') { OK "repo=$repo" } else { FAIL "repo=$repo" }

Write-Host '======== VERSIONS ========'
$smart = (ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt' 2>$null)
if ($smart) { $smart=$smart.Trim(); if ($smart -eq '20260717.22') { OK "smart=$smart frozen" } else { FAIL "smart=$smart expected .22" } } else { FAIL 'smart unreachable' }
$sepidz = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt' 2>$null)
if ($sepidz) { $sepidz=$sepidz.Trim(); if ($sepidz -eq '20260717.33') { OK "sepidz=$sepidz" } else { FAIL "sepidz=$sepidz expected .33" } } else { FAIL 'sepidz unreachable' }

Write-Host '======== STATIC TESTS ========'
foreach ($t in @('scripts\client\tests\test-connect-pipeline.ps1','scripts\client\tests\test-git-mode-deep.ps1')) {
  $tp = Join-Path $root $t
  if (-not (Test-Path $tp)) { Write-Host "WARN missing $t"; continue }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $tp | Out-Host
  if ($LASTEXITCODE -ne 0) { FAIL "$t exit=$LASTEXITCODE" } else { OK "$t" }
}

Write-Host '======== SEPIDZ LIVE ========'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q "$root\scripts\tmp\deep_final.py" 'sepidz@192.168.250.70:/tmp/deep_final.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_final.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\rdf.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\rdf.sh" 'sepidz@192.168.250.70:/tmp/rdf.sh'
ssh -o BatchMode=yes -o ConnectTimeout=300 sepidz@192.168.250.70 'bash /tmp/rdf.sh'
if ($LASTEXITCODE -ne 0) { FAIL "live deep exit=$LASTEXITCODE" } else { OK 'live deep' }

Write-Host '======== RESULT ========'
Write-Host "local_fail=$fail"
if ($fail -ne 0) { Write-Host 'ALL_DEEP_RED'; exit 1 }
Write-Host 'ALL_DEEP_GREEN'
exit 0
