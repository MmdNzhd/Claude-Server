$ErrorActionPreference = 'Continue'
Write-Host '=== KILL CONNECT BOOT/PS1 (not Cursor) ==='
Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object {
    $_.CommandLine -and
    $_.CommandLine -match 'connect-boot\.ps1|\\connect\.ps1' -and
    $_.CommandLine -notmatch 'Cursor|ClaudeServerCursor|diag-launch|patch-|sync-desk|finish-v|parse\.ps1|pub\.ps1'
  } |
  ForEach-Object {
    Write-Host "KILL $($_.ProcessId) $($_.Name)"
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  }
Start-Sleep -Milliseconds 500

# also orphan ssh -R tunnel for our connect if needed? leave tunnel for now - user can restart clean
$c=$false
$m = New-Object System.Threading.Mutex($false,'Global\ClaudeConnect',[ref]$c)
$g=$false
try { $g=$m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $g=$true; Write-Host 'ABANDONED' }
Write-Host "MUTEX_FREE=$g created_new=$c"
if ($g) { $m.ReleaseMutex() }
$m.Dispose()

# show blocked message path in connect-boot
$boot = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-boot.ps1'
Select-String -Path $boot -Pattern 'SINGLE_INSTANCE|blocked|already' | ForEach-Object { $_.Line.Trim() }

# try a non-interactive probe: can we start connect-boot briefly? Better not full UI.
# Just confirm mutex free and no procs
$left = @(Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'connect-boot\.ps1' -and $_.CommandLine -notmatch 'Cursor' })
Write-Host "REMAINING_BOOT=$($left.Count)"
Write-Host 'READY_TO_LAUNCH=1'
