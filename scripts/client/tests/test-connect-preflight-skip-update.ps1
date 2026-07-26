#Requires -Version 5.1
# test-connect-preflight-skip-update.ps1
# Task 5+: bootstrap handoff SKIP_UPDATE/SKIP_HEAL; preflight skips heal+update on healthy current path.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== connect-preflight skip update/heal via bootstrap handoff ===' -ForegroundColor Cyan

$bootPath = Get-ClientFile 'windows\connect-bootstrap.ps1'
$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
$boot = Get-Content -LiteralPath $bootPath -Raw
$pre = Get-Content -LiteralPath $prePath -Raw

Write-Host ''
Write-Host '--- Bootstrap handoff writer ---' -ForegroundColor DarkCyan

Assert ($boot -match 'claude-connect-preflight\.ok') 'bootstrap references preflight handoff file'
Assert ($boot -match 'SKIP_UPDATE') 'bootstrap handoff includes SKIP_UPDATE'
Assert ($boot -match 'skip canon already current') 'bootstrap still logs skip canon already current'
Assert ($boot -match 'Write-PreflightHandoff|Set-PreflightHandoff') 'bootstrap has Write-PreflightHandoff helper'

Write-Host ''
Write-Host '--- Preflight skip reader ---' -ForegroundColor DarkCyan

Assert ($pre -match 'Read-PreflightHandoff|Get-PreflightHandoff') 'preflight reads handoff file'
Assert ($pre -match 'Test-HealthyDeploy') 'preflight has healthy deploy check'
Assert ($pre -match 'SKIP_UPDATE') 'preflight checks SKIP_UPDATE from handoff'
Assert ($pre -match 'SKIP_HEAL') 'preflight checks SKIP_HEAL from handoff'

$updateBlock = [regex]::Match($pre, '(?s)\$isSepidz\s*=.*exit 0').Value
Assert ($updateBlock) 'preflight update block extracted'
Assert ($updateBlock -match 'SKIP_UPDATE|skipUpdate|skip.*update') 'update block gated on skip handoff'

$healBlockStart = $pre.IndexOf('$healPath = Join-Path')
$healBlockEnd = $pre.IndexOf('$isSepidz =', $healBlockStart)
$healBlock = if ($healBlockStart -ge 0 -and $healBlockEnd -gt $healBlockStart) {
    $pre.Substring($healBlockStart, $healBlockEnd - $healBlockStart)
} else { '' }
Assert ($healBlock -match 'SKIP_HEAL|skipHeal|Test-HealthyDeploy') 'heal block skips when handoff says healthy current'

Write-Host ''
Write-Host '--- Handoff file round-trip ---' -ForegroundColor DarkCyan

$handoffPath = Join-Path $env:TEMP 'claude-connect-preflight.ok'
Remove-Item -LiteralPath $handoffPath -Force -ErrorAction SilentlyContinue
try {
    @(
        'SKIP_UPDATE=1',
        'SKIP_HEAL=1',
        'REMOTE_VER=20260726.02',
        'LOCAL_VER=20260726.02'
    ) | Set-Content -LiteralPath $handoffPath -Encoding ASCII

    $lines = @{}
    Get-Content -LiteralPath $handoffPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { $lines[$Matches[1]] = $Matches[2] }
    }
    Assert ($lines['SKIP_UPDATE'] -eq '1') 'handoff SKIP_UPDATE round-trip'
    Assert ($lines['SKIP_HEAL'] -eq '1') 'handoff SKIP_HEAL round-trip'
    Assert ($lines['REMOTE_VER'] -eq '20260726.02') 'handoff REMOTE_VER round-trip'
}
finally {
    Remove-Item -LiteralPath $handoffPath -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All connect-preflight skip-update tests passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail test(s) failed." -ForegroundColor Red
exit 1
