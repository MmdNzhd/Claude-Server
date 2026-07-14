# test-verify-perf-gates.ps1 - gate script rejects baseline, accepts post-fix sample
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$verify = Join-Path $PSScriptRoot 'verify-perf-gates.ps1'
Assert (Test-Path $verify) 'verify-perf-gates.ps1 exists'

$good = Join-Path $env:TEMP ("connect-perf-good-{0}.log" -f [guid]::NewGuid().ToString('n'))
@(
    '[2026-07-14 18:00:00.000] [INFO] ======== session start v20260714.5 user=Smart elevated=yes pid=12345 ========'
    '[2026-07-14 18:00:05.000] [INFO] STEP begin: Opening Cursor'
    '[2026-07-14 18:00:07.500] [DEBUG] PERF[entry_on_folder] ms=0 cim_total=0 result=True skipped=known_on_folder'
    '[2026-07-14 18:00:07.501] [INFO] LAUNCH_SKIP: already on correct folder - keeping Cursor open'
    '[2026-07-14 18:00:07.502] [DEBUG] PERF[launch_total] ms=450 cim_total=2 path=skip'
    '[2026-07-14 18:00:07.503] [INFO] STEP end: Opening Cursor ok ms=520 detail=/home/smart/mounts/ai'
    '[2026-07-14 18:00:07.600] [DEBUG] PERF[diag_process_snapshot] ms=0 skipped=light_session_open'
    '[2026-07-14 18:00:07.601] [DEBUG] PERF[session_open_summary] ms=0 mount_ms=2100 auth_ms=0 open_ms=520 diag_ms=95 ssh_total_ms=4200 ssh_count=3 cim_total=2 fixes=F1,F2,F3,F5,F4,F7 version=20260714.5'
) | Set-Content -Path $good -Encoding UTF8

$bad = Join-Path $env:TEMP ("connect-perf-bad-{0}.log" -f [guid]::NewGuid().ToString('n'))
@(
    '[2026-07-14 14:29:29.210] [INFO] ======== session start v20260714.2 user=User elevated=yes pid=999 ========'
    '[2026-07-14 14:29:29.210] [INFO] STEP begin: Opening Cursor'
    '[2026-07-14 14:29:29.210] [INFO] LAUNCH_BEGIN: on_folder=False'
    '[2026-07-14 14:29:30.542] [DEBUG] SNAPSHOT[BEGIN] ...'
    '[2026-07-14 14:29:35.470] [DEBUG] LAUNCH_POLL: strategy=folder-uri-classic elapsed=2s on_folder=True agent_home=False'
    '[2026-07-14 14:29:38.951] [INFO] LAUNCH_ATTEMPT_RESULT: n=1 strategy=folder-uri-classic on_folder=True'
    '[2026-07-14 14:29:44.153] [INFO] LAUNCH_OK: strategy=folder-uri-classic attempt=1'
    '[2026-07-14 14:29:44.155] [INFO] STEP end: Opening Cursor ok ms=15242 detail=/home/aria/mounts/smartclub'
) | Set-Content -Path $bad -Encoding UTF8

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -LogPath $good
    $goodRc = $LASTEXITCODE
    Assert ($goodRc -eq 0) 'post-fix sample passes all gates'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -LogPath $bad
    $badRc = $LASTEXITCODE
    Assert ($badRc -ne 0) 'pre-fix baseline fails gates (expected)'

    if (Test-Path (Join-Path $script:RepoRoot 'logs\connect.log.1')) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -LogPath (Join-Path $script:RepoRoot 'logs\connect.log.1')
        $baseRc = $LASTEXITCODE
        Assert ($baseRc -ne 0) 'aria baseline log fails gates (proves regression detector)'
    }
} finally {
    Remove-Item $good,$bad -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'All verify-perf-gates tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
