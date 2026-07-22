$base = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$day = 'connect-20260721.log'
Write-Output ("watermark=" + (Get-Content -LiteralPath (Join-Path $base "$day.sync-offset") -Raw))
Write-Output ("localBytes=" + (Get-Item (Join-Path $base $day)).Length)
$pend = Join-Path $base "$day.sync-pending"
Write-Output ("pendingExists=" + (Test-Path -LiteralPath $pend))
$lines = [System.IO.File]::ReadAllLines((Join-Path $base $day))
Write-Output ("localLines=" + $lines.Length)
$u = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in $lines) { [void]$u.Add($l) }
Write-Output ("localUnique=" + $u.Count)
$starts = ($lines | Where-Object { $_ -match 'session start' }).Count
Write-Output ("localSessionStarts=" + $starts)
Write-Output ("dupPct=" + [math]::Round(100*(1 - $u.Count/[double]$lines.Length), 2))
# sample LOG_SYNC on local
$ls = $lines | Where-Object { $_ -match 'LOG_SYNC_' }
Write-Output ("localLogSyncTotal=" + @($ls).Count)
Write-Output ("localLogSyncUnique=" + @($ls | Select-Object -Unique).Count)
$ls | Select-Object -Unique | Select-Object -First 20 | ForEach-Object { Write-Output $_ }
Write-Output '---YDAY---'
$y='connect-20260720.log'
Write-Output ("y_wm=" + (Get-Content -LiteralPath (Join-Path $base "$y.sync-offset") -Raw))
Write-Output ("y_bytes=" + (Get-Item (Join-Path $base $y)).Length)
$yl = [System.IO.File]::ReadAllLines((Join-Path $base $y))
Write-Output ("y_lines=" + $yl.Length)
$yu = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in $yl) { [void]$yu.Add($l) }
Write-Output ("y_unique=" + $yu.Count)
Write-Output ("y_starts=" + ($yl | Where-Object { $_ -match 'session start' }).Count)
