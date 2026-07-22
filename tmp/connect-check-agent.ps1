$log = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-20260721.log"
if (-not (Test-Path -LiteralPath $log)) { Write-Output "LOG_MISSING: $log"; exit 2 }
$all = Get-Content -LiteralPath $log -ErrorAction Stop
Write-Output "===LAST80==="
$all | Select-Object -Last 80
Write-Output "===ANALYSIS==="
$idx = -1
for ($i = $all.Count - 1; $i -ge 0; $i--) {
  if ($all[$i] -match 'v20260721\.') { $idx = $i; break }
}
$latestStart = if ($idx -ge 0) { $all[$idx] } else { $null }
Write-Output ("LATEST_START_LINE: " + $latestStart)
$version = $null; $sessionId = $null
if ($latestStart -match 'v(20260721\.[0-9]+)') { $version = $Matches[1] }
if ($latestStart -match 'session[=:\s]+([A-Za-z0-9_-]+)') { $sessionId = $Matches[1] }
Write-Output ("PARSED_VERSION: " + $version)
Write-Output ("PARSED_SESSION: " + $sessionId)
Write-Output ("START_IDX: " + $idx + " TOTAL: " + $all.Count)
$sessionLines = if ($idx -ge 0) { $all[$idx..($all.Count-1)] } else { $all | Select-Object -Last 80 }
Write-Output "===SESSION_FROM_START==="
$sessionLines
Write-Output "===SSH_R==="
$ssh = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match '-R' })
Write-Output ("LIVE_SSH_R_COUNT: " + $ssh.Count)
foreach ($p in $ssh) {
  $cl = [string]$p.CommandLine
  if ($cl.Length -gt 240) { $cl = $cl.Substring(0,240) + "..." }
  Write-Output ("PID=" + $p.ProcessId + " CMD=" + $cl)
}
