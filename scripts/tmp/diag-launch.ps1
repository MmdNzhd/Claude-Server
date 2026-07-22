$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host "=== LOG TAIL ==="
if (Test-Path $log) {
  Write-Host ("LOG_SIZE=" + (Get-Item $log).Length)
  Get-Content $log -Tail 80
} else { Write-Host 'NO_LOG' }

Write-Host "=== MUTEX ==="
$c=$false; $m=$null
try {
  $m = New-Object System.Threading.Mutex($false,'Global\ClaudeConnect',[ref]$c)
  $g=$false
  try { $g=$m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $g=$true }
  Write-Host "MUTEX_FREE=$g created_new=$c"
  if ($g) { $m.ReleaseMutex() }
} catch { Write-Host "MUTEX_ERR=$($_.Exception.Message)" }
finally { if ($m) { $m.Dispose() } }

Write-Host "=== CONNECT PROCS ==="
Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'connect-boot|connect\.ps1|connect\.bat' -and $_.CommandLine -notmatch 'Cursor|ClaudeServerCursor|patch-|diag-|sync-desk|finish-v|parse\.ps1' } |
  ForEach-Object { Write-Host ("PID=$($_.ProcessId) PPID=$($_.ParentProcessId) NAME=$($_.Name) CMD=$($_.CommandLine.Substring(0,[Math]::Min(180,$_.CommandLine.Length)))") }

Write-Host "=== LAUNCH TREE VER ==="
foreach ($t in @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows')
)) {
  $vf = Join-Path $t 'connect-version.txt'
  $v = if (Test-Path $vf) { (Get-Content $vf -Raw).Trim() } else { 'MISSING' }
  $elev = if (Test-Path (Join-Path $t 'connect.ps1')) { [int]((Get-Content (Join-Path $t 'connect.ps1') -Raw) -match 'Do NOT -Wait') } else { -1 }
  Write-Host "PATH=$t ver=$v elev_fix=$elev"
}

Write-Host "=== RECENT BOOTSTRAP/FAIL ==="
if (Test-Path $log) {
  Select-String -Path $log -Pattern 'BOOTSTRAP|FAIL |SINGLE_INSTANCE|ADMIN_ELEVATE|session start|OUTDATED|UPDATE_RELAUNCH|blocked' |
    Select-Object -Last 40 | ForEach-Object { $_.Line }
}
