#Requires -Version 5.1
# test-run-id-multi-ui.ps1 - dual connect.bat must not share one RUN_ID via TEMP handoff race.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; throw "ASSERT: $Msg" }
}

Write-Host '=== test-run-id-multi-ui ===' -ForegroundColor Cyan

$batPath = Get-ClientFile 'windows\connect.bat'
$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
$bat = Get-Content -LiteralPath $batPath -Raw
$pre = Get-Content -LiteralPath $prePath -Raw

Assert ($bat -match 'Multi-UI: mint a unique RUN_ID') 'bat documents multi-UI RUN_ID mint'
$mintAt = $bat.IndexOf('Multi-UI: mint a unique RUN_ID')
$preAt = $bat.IndexOf('if exist "%HERE%connect-preflight.ps1"')
Assert ($mintAt -ge 0 -and $preAt -gt $mintAt) 'mint precedes preflight'
Assert ($bat -match 'if not defined CLAUDE_CONNECT_RUN_ID if exist "%TEMP%\\claude-connect-run-id\.txt"') 'shared file read is gated on unset'
Assert ($pre -match 'claude-connect-run-id\.\{0\}\.txt') 'preflight per-PID handoff'
Assert ($pre -match 'if \(-not \(Test-Path -LiteralPath \$sharedHandoff\)\)') 'preflight does not stomp existing shared handoff'

Write-Host '--- Runtime: two parallel bat-like mints keep distinct ids ---' -ForegroundColor DarkCyan

$shared = Join-Path $env:TEMP ('claude-connect-run-id-multiui-' + [guid]::NewGuid().ToString('N') + '.txt')
$probe = Join-Path $env:TEMP ('claude-connect-run-id-probe-' + [guid]::NewGuid().ToString('N') + '.cmd')
$out1 = Join-Path $env:TEMP ('rid-out1-' + [guid]::NewGuid().ToString('N') + '.txt')
$out2 = Join-Path $env:TEMP ('rid-out2-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
    $sharedPs = $shared.Replace("'", "''")
    $probeBody = @"
@echo off
setlocal EnableDelayedExpansion
REM Fresh UI: parent must not leak a sticky RUN_ID into this process.
set "CLAUDE_CONNECT_RUN_ID="
if not defined CLAUDE_CONNECT_RUN_ID (
  for /f %%I in ('powershell -NoProfile -WindowStyle Hidden -Command "[guid]::NewGuid().ToString('N').Substring(0,12)"') do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
powershell -NoProfile -WindowStyle Hidden -Command "Set-Content -LiteralPath '$sharedPs' -Value `$env:CLAUDE_CONNECT_RUN_ID -Encoding ASCII"
if not defined CLAUDE_CONNECT_RUN_ID if exist "$shared" (
  for /f "usebackq delims=" %%I in ("$shared") do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
echo !CLAUDE_CONNECT_RUN_ID!
"@
    Set-Content -LiteralPath $probe -Value $probeBody -Encoding ASCII

    # Clear inherited RUN_ID so Start-Process children mimic a fresh double-click.
    $prevRunId = $env:CLAUDE_CONNECT_RUN_ID
    Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue
    try {
        $p1 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probe`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $out1 -RedirectStandardError ($out1 + '.err')
        Start-Sleep -Milliseconds 30
        $p2 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probe`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $out2 -RedirectStandardError ($out2 + '.err')
    } finally {
        if ($null -ne $prevRunId -and "$prevRunId" -ne '') {
            $env:CLAUDE_CONNECT_RUN_ID = $prevRunId
        }
    }
    $null = $p1.WaitForExit(15000)
    $null = $p2.WaitForExit(15000)
    Assert ($p1.HasExited -and $p2.HasExited) 'both probe processes exited'
    Assert ((Test-Path -LiteralPath $out1) -and (Test-Path -LiteralPath $out2)) 'probe stdout files exist'
    $id1 = ((Get-Content -LiteralPath $out1 -ErrorAction Stop | Select-Object -First 1) + '').Trim()
    $id2 = ((Get-Content -LiteralPath $out2 -ErrorAction Stop | Select-Object -First 1) + '').Trim()
    Assert ($id1 -match '^[0-9a-fA-F]{12}$') "ui1 RUN_ID format ($id1)"
    Assert ($id2 -match '^[0-9a-fA-F]{12}$') "ui2 RUN_ID format ($id2)"
    Assert ($id1 -ne $id2) "dual UI RUN_IDs distinct ($id1 vs $id2)"
}
finally {
    Remove-Item -LiteralPath $probe, $shared, $out1, $out2 -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
