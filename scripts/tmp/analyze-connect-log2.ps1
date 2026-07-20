#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$out = 'D:\Smart\Claude-Code-Server\scripts\tmp\connect-log-analysis.txt'
if (-not (Test-Path $path)) { "MISS $path" | Set-Content $out; exit 1 }
$i = Get-Item $path
$lines = Get-Content $path
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("FILE=$($i.FullName) size=$($i.Length) mtime=$($i.LastWriteTime) lines=$($lines.Count)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== HEAD 50 ===')
($lines | Select-Object -First 50) | ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== TAIL 100 ===')
($lines | Select-Object -Last 100) | ForEach-Object { [void]$sb.AppendLine($_) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== COUNTS ===')
foreach ($pat in @(
  @{N='v20260717.1'; P='20260717\.1'},
  @{N='v20260715'; P='20260715'},
  @{N='LAUNCH_KILL_SKIP'; P='LAUNCH_KILL_SKIP'},
  @{N='preserve_open_windows'; P='preserve_open_windows'},
  @{N='LAUNCH_RETRY_NO_KILL'; P='LAUNCH_RETRY_NO_KILL'},
  @{N='pre_launch_agent_or_new_window'; P='pre_launch_agent_or_new_window'},
  @{N='ORPHAN'; P='ORPHAN'},
  @{N='ERROR'; P='\bERROR\b'},
  @{N='FAIL'; P='\bFAIL\b'},
  @{N='WARN'; P='\bWARN\b'},
  @{N='Client update'; P='Client update|Updated to'},
  @{N='Force kill reason'; P='Reason=.*Force|-Force'}
)) {
  $c = @($lines | Select-String -Pattern $pat.P).Count
  [void]$sb.AppendLine(("{0}={1}" -f $pat.N, $c))
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== VERSION LINES ===')
$lines | Select-String -Pattern '2026071[0-9]\.\d+|ConnectVersion|Client version|Updated to|update available|ScriptConnect' |
  ForEach-Object { [void]$sb.AppendLine(("{0}: {1}" -f $_.LineNumber, $_.Line.Trim())) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== KILL/CURSOR (last 80 matches) ===')
$lines | Select-String -Pattern 'KILL|preserve_open|Force|ORPHAN|CursorServer|profile_count|new.window|LAUNCH_' |
  Select-Object -Last 80 |
  ForEach-Object { [void]$sb.AppendLine(("{0}: {1}" -f $_.LineNumber, $_.Line.Trim())) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== ERROR/WARN (all) ===')
$lines | Select-String -Pattern '\bERROR\b|\bFAIL\b|Exception|\bWARN\b|WARNING|fatal|denied|Timed out|timeout' |
  ForEach-Object { [void]$sb.AppendLine(("{0}: {1}" -f $_.LineNumber, $_.Line.Trim())) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== LAST SESSION CHUNK (from last ConnectVersion or ====) ===')
$startIdx = 0
for ($n=$lines.Count-1; $n -ge 0; $n--) {
  if ($lines[$n] -match 'ConnectVersion|====|START CONNECT|BEGIN|connect\.ps1 start|Session start') { $startIdx = $n; break }
}
# better: find last occurrence of version line or banner
for ($n=$lines.Count-1; $n -ge 0; $n--) {
  if ($lines[$n] -match '20260717\.1|Connect version|Client v') { $startIdx = [Math]::Max(0, $n-30); break }
}
($lines[$startIdx..($lines.Count-1)]) | ForEach-Object { [void]$sb.AppendLine($_) }

Set-Content -Path $out -Value $sb.ToString() -Encoding UTF8
Write-Output "WROTE $out chars=$($sb.Length)"
