# test-tunnel-job-object-live.ps1 - #P2 LIVE: assigning a real spawned process to the shared
# KILL_ON_JOB_CLOSE job object, then closing that job, must actually terminate the process at
# the OS level - not merely call the right-looking Win32 API names.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Tunnel/sidecar Job Object #P2 (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
foreach ($n in @('Initialize-CursorProxySidecarJob', 'Add-CursorProxySidecarJobProcess', 'Stop-CursorProxySidecarJob')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

$member = $null
$control = $null
try {
    $member = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120') -WindowStyle Hidden -PassThru
    $control = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120') -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 400
    Assert (-not $member.HasExited) 'member (about to be job-assigned) process actually started'
    Assert (-not $control.HasExited) 'control (never job-assigned) process actually started'

    Add-CursorProxySidecarJobProcess -Process $member

    # Real KILL_ON_JOB_CLOSE proof: closing the job handle must kill only the assigned member.
    Stop-CursorProxySidecarJob

    $deadline = (Get-Date).AddSeconds(6)
    $memberDead = $false
    while ((Get-Date) -lt $deadline) {
        if ($member.HasExited) { $memberDead = $true; break }
        Start-Sleep -Milliseconds 200
    }
    Assert $memberDead 'job-assigned member process was actually killed when the job handle closed (real KILL_ON_JOB_CLOSE effect, not just an API call)'
    Assert (-not $control.HasExited) 'the unrelated control process (never added to this job) survived - proves the job only affects its own members, no blast radius'
} finally {
    foreach ($p in @($member, $control)) {
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch { } }
    }
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
