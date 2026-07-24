# test-tunnel-job-object.ps1 - #P2 main reverse-tunnel process must die with Connect (KILL_ON_JOB_CLOSE)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Tunnel Job Object #P2 (static) ===' -ForegroundColor Cyan

$s = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

$spawnPattern = [regex]::Escape('$BgTunnel.Value = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList ($sshArgs + @($Alias))')
$m = [regex]::Match($s, $spawnPattern)
Assert ($m.Success) 'Ensure-SessionTunnel main tunnel spawn line found'

if ($m.Success) {
    $window = $s.Substring($m.Index, [Math]::Min(600, $s.Length - $m.Index))
    Assert ($window -match 'Add-CursorProxySidecarJobProcess') 'tunnel process gets assigned to KILL_ON_JOB_CLOSE job right after spawn'
    Assert ($window -match 'Get-Command\s+Add-CursorProxySidecarJobProcess\s+-ErrorAction\s+SilentlyContinue') 'job-object call is defensively guarded (load-order safe)'
    Assert ($window -match '-Process\s+\$BgTunnel\.Value') 'the exact spawned tunnel process object is passed to the job'
}

$sidecar = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
Assert ($sidecar -match 'function Add-CursorProxySidecarJobProcess') 'shared job-assign function still defined in sidecar file (reused, not duplicated)'

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
