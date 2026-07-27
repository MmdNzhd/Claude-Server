#Requires -Version 5.1
# test-exe-spaced-path-launch.ps1
# Regression: Start-Process -File with paths containing spaces must quote the script path.
# Without quotes, setup-worker never runs after relocate under folders like
# C:\Temp\test for update\Claude-Connect\{ver}\src — EXE "does nothing" on click.
$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== EXE spaced-path launch (worker/boot -File quoting) ==='
Write-Host ''

$launch = Get-Content -LiteralPath (Join-Path $RepoRoot 'publish\_setup-launch-body.ps1') -Raw
$worker = Get-Content -LiteralPath (Join-Path $RepoRoot 'publish\_setup-worker-body.ps1') -Raw

Assert ($launch -match '`"\$workerDest`"') 'setup-launch embeds quoted workerDest for -File'
Assert ($worker -match '`"\$boot`"') 'setup-worker embeds quoted $boot for -File'
Assert ($launch -match 'Copy-Item -LiteralPath \$workerSrc -Destination \$workerDest -Force') 'setup-launch always refreshes setup-worker.ps1'
Assert (-not ($launch -match 'if \(\$didInstall -or -not \(Test-Path -LiteralPath \$workerDest\)\)')) 'setup-launch no longer skips worker refresh on fast path'

# Live probe: ArgumentList array without quotes breaks under spaces; with quotes works.
$probeRoot = Join-Path $env:TEMP ('cc spaced launch ' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$srcDir = Join-Path $probeRoot 'Claude-Connect\20990101.1\src'
New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
$marker = Join-Path $env:TEMP ('cc-spaced-marker-' + [guid]::NewGuid().ToString('N') + '.txt')
$script = Join-Path $srcDir 'probe-worker.ps1'
Set-Content -LiteralPath $script -Value ("Set-Content -LiteralPath '" + $marker.Replace("'", "''") + "' -Value 'ok'") -Encoding UTF8

Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
Start-Process -FilePath 'powershell.exe' -WorkingDirectory $srcDir -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script
) -WindowStyle Hidden | Out-Null
Start-Sleep -Milliseconds 800
Assert (-not (Test-Path -LiteralPath $marker)) 'LIVE unquoted -File with spaces does NOT run (bug baseline)'

Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
Start-Process -FilePath 'powershell.exe' -WorkingDirectory $srcDir -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`""
) -WindowStyle Hidden | Out-Null
Start-Sleep -Milliseconds 800
Assert (Test-Path -LiteralPath $marker) 'LIVE quoted -File with spaces DOES run (fix)'

try { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("RESULT: {0} pass / 0 fail" -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
exit 1
