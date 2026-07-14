# test-parse-connect-perf.ps1 - parse-connect-perf.ps1 smoke test (no live connect.log required)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== parse-connect-perf ===' -ForegroundColor Cyan
Write-Host ''

$parser = Join-Path $PSScriptRoot 'parse-connect-perf.ps1'
Assert (Test-Path $parser) 'parse-connect-perf.ps1 exists'

$sample = Join-Path $env:TEMP ("connect-perf-sample-{0}.log" -f [guid]::NewGuid().ToString('n'))
@(
    '[2026-07-14 14:27:27.917] [INFO] STEP begin: Opening Cursor'
    '[2026-07-14 14:28:04.865] [INFO] STEP end: Opening Cursor ok ms=2500 detail=/home/smart/mounts/ai'
    '[2026-07-14 14:28:05.000] [DEBUG] PERF[launch_total] ms=2400 cim_total=4 path=ok strategy=folder-uri-classic'
    '[2026-07-14 14:28:05.100] [DEBUG] PERF[session_open_summary] ms=0 mount_ms=2300 auth_ms=0 open_ms=2500 diag_ms=120 ssh_total_ms=4500 ssh_count=3 cim_total=4 fixes=F1,F2,F3,F5,F4,F7 version=20260714.4'
    '[2026-07-14 14:28:05.200] [INFO] LAUNCH_OK: strategy=folder-uri-classic attempt=1'
) | Set-Content -Path $sample -Encoding UTF8

try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $parser -LogPath $sample 2>&1 | Out-String
    Assert ($out -match 'Opening Cursor gate: 2500 ms') 'parser reports Opening Cursor step ms'
    Assert ($out -match 'SNAPSHOT lines: 0') 'parser counts SNAPSHOT lines'
    Assert ($out -match 'Session summary:') 'parser shows session summary'
    Assert ($out -match 'mount_ms=2300') 'parser includes session summary fields'
} finally {
    Remove-Item $sample -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
