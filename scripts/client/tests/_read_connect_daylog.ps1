$ErrorActionPreference = 'Continue'
$p = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
Write-Output ("LOGDIR=" + $p + " exists=" + (Test-Path -LiteralPath $p))
Get-ChildItem -LiteralPath $p -Filter 'connect-*.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 3 |
  ForEach-Object { Write-Output ("FILE {0} len={1} mtime={2:o}" -f $_.Name, $_.Length, $_.LastWriteTime) }
$latest = Get-ChildItem -LiteralPath $p -Filter 'connect-*.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latest) { Write-Output 'NO_LOG'; exit 0 }
Write-Output ("==== TAIL " + $latest.FullName)
Get-Content -LiteralPath $latest.FullName -Tail 80
Write-Output '==== LAST_CONNECT_VERSION ===='
Select-String -LiteralPath $latest.FullName -Pattern 'CONNECT_VERSION=' |
  Select-Object -Last 5 | ForEach-Object { $_.Line }
Write-Output '==== LAST_WARN_ERROR ===='
Select-String -LiteralPath $latest.FullName -Pattern '\[WARN\]|\[ERROR\]' |
  Select-Object -Last 30 | ForEach-Object { $_.Line }
Write-Output '==== STEP_END_SLOW ===='
Select-String -LiteralPath $latest.FullName -Pattern 'STEP end:' |
  Select-Object -Last 40 | ForEach-Object { $_.Line }
Write-Output '==== TUNNEL_SOFT_FAIL ===='
Select-String -LiteralPath $latest.FullName -Pattern 'TUNNEL_SYNC soft_fail|banner_miss|reseed_needed|auto_relaunch|need_mount|ACQUIRE_FAST' |
  Select-Object -Last 40 | ForEach-Object { $_.Line }
