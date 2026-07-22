$log = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-20260721.log"
$lines = Get-Content $log
Write-Output "=== Real LAUNCH_KILL (not SKIP) after 19:07 ==="
$real = @()
foreach ($line in $lines) {
    if ($line -match 'LAUNCH_KILL_SKIP') { continue }
    if ($line -notmatch 'LAUNCH_KILL') { continue }
    if ($line -match '\[2026-07-21 19:0[7-9]:' -or $line -match '\[2026-07-21 19:[1-5][0-9]:' -or $line -match '\[2026-07-21 2[0-3]:') {
        $real += $line
    }
}
if ($real.Count -eq 0) { Write-Output "NONE" } else { $real }
Write-Output "=== All LAUNCH_KILL* after 19:07 ==="
foreach ($line in $lines) {
    if ($line -notmatch 'LAUNCH_KILL') { continue }
    if ($line -match '\[2026-07-21 19:0[7-9]:' -or $line -match '\[2026-07-21 19:[1-5][0-9]:' -or $line -match '\[2026-07-21 2[0-3]:') { Write-Output $line }
}
