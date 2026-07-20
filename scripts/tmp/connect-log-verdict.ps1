#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
if (-not (Test-Path $path)) { Write-Output "MISS $path"; exit 1 }
$i = Get-Item $path
$lines = Get-Content $path
Write-Output "FILE=$($i.FullName)"
Write-Output "SIZE=$($i.Length) MTIME=$($i.LastWriteTime) LINES=$($lines.Count)"
Write-Output ''

# counts
$map = [ordered]@{
  'v20260717.1' = '20260717\.1'
  'v20260715' = '20260715'
  'v20260714' = '20260714'
  'LAUNCH_KILL_SKIP' = 'LAUNCH_KILL_SKIP'
  'preserve_open_windows' = 'preserve_open_windows'
  'LAUNCH_RETRY_NO_KILL' = 'LAUNCH_RETRY_NO_KILL'
  'pre_launch_agent_or_new_window' = 'pre_launch_agent_or_new_window'
  'ORPHAN' = 'ORPHAN'
  'ERROR' = '\bERROR\b'
  'FAIL' = '\bFAIL\b'
  'WARN' = '\bWARN\b'
  'Client update' = 'Client update|Updated to'
  'Force tree kill' = 'Stop-CursorServerProfileTreeIfNeeded.*-Force|Reason=.pre_launch'
}
foreach ($k in $map.Keys) {
  $c = @($lines | Select-String -Pattern $map[$k]).Count
  Write-Output ("COUNT {0}={1}" -f $k, $c)
}

Write-Output ''
Write-Output 'VERSION_HITS:'
$lines | Select-String -Pattern '2026071[0-9]\.\d+|ConnectVersion\s*=' |
  Select-Object -Last 30 |
  ForEach-Object { Write-Output ("{0}|{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Output ''
Write-Output 'KILL_HITS_LAST20:'
$lines | Select-String -Pattern 'LAUNCH_KILL_SKIP|preserve_open_windows|LAUNCH_RETRY_NO_KILL|pre_launch_agent|Stop-CursorServerProfileTreeIfNeeded' |
  Select-Object -Last 20 |
  ForEach-Object { Write-Output ("{0}|{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Output ''
Write-Output 'ORPHAN_HITS_LAST15:'
$lines | Select-String -Pattern 'ORPHAN' |
  Select-Object -Last 15 |
  ForEach-Object { Write-Output ("{0}|{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Output ''
Write-Output 'ERROR_WARN_LAST40:'
$lines | Select-String -Pattern '\bERROR\b|\bFAIL\b|Exception|\bWARN\b|WARNING|Timed out|Permission denied' |
  Select-Object -Last 40 |
  ForEach-Object { Write-Output ("{0}|{1}" -f $_.LineNumber, $_.Line.Trim()) }

Write-Output ''
Write-Output 'TAIL_60:'
$lines | Select-Object -Last 60 | ForEach-Object { Write-Output $_ }

# Infer last session version used
$lastVer = $null
$verHits = $lines | Select-String -Pattern '2026071[0-9]\.\d+'
if ($verHits) { $lastVer = $verHits[-1].Matches[0].Value }
Write-Output ''
Write-Output ("LAST_VERSION_SEEN=$lastVer")
$hasNewKill = (@($lines | Select-String 'preserve_open_windows|LAUNCH_KILL_SKIP|LAUNCH_RETRY_NO_KILL').Count -gt 0)
$hasOldKill = (@($lines | Select-String 'pre_launch_agent_or_new_window').Count -gt 0)
Write-Output ("HAS_NEW_KILL_LOGS=$hasNewKill")
Write-Output ("HAS_OLD_FORCE_KILL_LOGS=$hasOldKill")
