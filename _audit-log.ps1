$log = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-20260721.log"
if (-not (Test-Path $log)) { Write-Output "LOG_MISSING"; exit }
$lines = Get-Content $log
Write-Output "=== LAUNCH_KILL after 19:07 ==="
$found = $false
foreach ($line in $lines) {
    if ($line -notmatch 'LAUNCH_KILL') { continue }
    if ($line -match '\[2026-07-21 19:0[7-9]:' -or $line -match '\[2026-07-21 19:[1-5][0-9]:' -or $line -match '\[2026-07-21 2[0-3]:') {
        Write-Output $line
        $found = $true
    }
}
if (-not $found) { Write-Output "NO_LAUNCH_KILL_AFTER_1907" }
Write-Output "=== LAUNCH_KILL_SKIP auth after 19:07 (sample) ==="
foreach ($line in $lines) {
    if ($line -notmatch 'LAUNCH_KILL') { continue }
    if ($line -match 'auth_relaunch_never_kill|hard_refuse') {
        if ($line -match '\[2026-07-21 19:' -or $line -match '\[2026-07-21 2[0-3]:') { Write-Output $line }
    }
}
