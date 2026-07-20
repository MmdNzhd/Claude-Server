#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$lines = Get-Content $path
function Slice([int]$from, [int]$to) {
  $a = [Math]::Max(1,$from); $b = [Math]::Min($lines.Count,$to)
  for ($n=$a; $n -le $b; $n++) { Write-Output ("{0}|{1}" -f $n, $lines[$n-1]) }
}
function Ts([int]$ln) {
  if ($ln -lt 1 -or $ln -gt $lines.Count) { return $null }
  if ($lines[$ln-1] -match '^\[([^\]]+)\]') { return [datetime]$Matches[1] }
  return $null
}

Write-Output ("FILE_LINES=" + $lines.Count)
Write-Output '===== A) launch OK -> first TUNNEL_DOWN ====='
Slice 158 240
Write-Output '===== B) orphan -> remount ====='
Slice 255 340
Write-Output '===== C) launch skip -> TUNNEL_DOWN2 -> RECOVERY_END ====='
Slice 372 470
Write-Output '===== D) final OK diag ====='
Slice 490 545
Write-Output '===== E) ACTIVE_MOUNT FLIPS ====='
$lines | Select-String -Pattern 'ACTIVE_MOUNT|PUSH_CONF.*active_mount|CLEAR_MOUNT' | ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '===== F) DELTAS FROM LAUNCH_OK ====='
$events = @(
  @{L=158; N='LAUNCH_OK'},
  @{L=160; N='STEP_END_OPEN'},
  @{L=172; N='TUNNEL_UP_FALSE_1'},
  @{L=189; N='ERROR_TUNNEL_DOWN_1'},
  @{L=204; N='MOUNT_STILL_OK_1'},
  @{L=208; N='EDITOR_ON_FOLDER_1'},
  @{L=229; N='WARN_AUTO_RECONNECT'},
  @{L=233; N='CLEAR_MOUNT_SKIP_EDITOR'},
  @{L=237; N='MOUNT_DOWN_DONE'},
  @{L=263; N='KILL_ORPHAN_SSH'},
  @{L=269; N='PORT_RELEASED'},
  @{L=287; N='TUNNEL_SPAWN_2'},
  @{L=294; N='TUNNEL_OK_2'},
  @{L=333; N='REMOUNT_OK'},
  @{L=382; N='LAUNCH_SKIP_KEEP'},
  @{L=413; N='ERROR_TUNNEL_DOWN_2'},
  @{L=427; N='TUNNEL_DIAG2_DETAIL'},
  @{L=462; N='RECOVERY_END'},
  @{L=495; N='SESSION_OK'},
  @{L=511; N='EDITOR_STATE_FINAL'}
)
$t0 = Ts 158
foreach ($e in $events) {
  $t = Ts $e.L
  $delta = if ($t0 -and $t) { '{0:N3}' -f ($t - $t0).TotalSeconds } else { '?' }
  $abs = if ($t) { $t.ToString('HH:mm:ss.fff') } else { '?' }
  $snippet = if ($e.L -le $lines.Count) { ($lines[$e.L-1] -replace '^\[.*?\]\s*','') } else { '' }
  if ($snippet.Length -gt 140) { $snippet = $snippet.Substring(0,140) + '...' }
  Write-Output ("+{0,8}s  L{1,-5}  {2,-28}  {3}  | {4}" -f $delta, $e.L, $e.N, $abs, $snippet)
}
Write-Output '===== G) SSH exit!=0 context ====='
foreach ($f in ($lines | Select-String -Pattern 'SSH_END exit=[1-9]')) {
  $n=$f.LineNumber
  Write-Output ("--- @{0} ---" -f $n)
  for ($k=[Math]::Max(1,$n-2); $k -le $n; $k++) { Write-Output ("{0}|{1}" -f $k, $lines[$k-1].Trim()) }
}
Write-Output '===== H) second failure tunnel fields ====='
Slice 385 432
Write-Output '===== I) EDITOR exact ====='
$lines | Select-String -Pattern 'LAUNCH_BEGIN:|LAUNCH_PLAN:|LAUNCH_OK:|LAUNCH_SKIP:|EDITOR_DECISION:|EDITOR on_folder=|EDITOR state=' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '===== J) tunnel false transitions near failures ====='
for ($n=160; $n -le 230; $n++) {
  if ($lines[$n-1] -match 'TUNNEL_UP|TUNNEL_BANNER port=|TUNNEL_SYNC ok|connection dropped') {
    Write-Output ("{0}|{1}" -f $n, $lines[$n-1])
  }
}
for ($n=385; $n -le 430; $n++) {
  if ($lines[$n-1] -match 'TUNNEL_UP|TUNNEL_BANNER port=|TUNNEL up=|banner=') {
    Write-Output ("{0}|{1}" -f $n, $lines[$n-1])
  }
}
Write-Output 'DONE'
