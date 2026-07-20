#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$lines = Get-Content $path
Write-Output ("LINES=" + $lines.Count + " LAST=" + $lines[-1].Substring(0,[Math]::Min(80,$lines[-1].Length)))

function Slice($a,$b){ for($n=$a;$n -le [Math]::Min($b,$lines.Count);$n++){ Write-Output ("{0}|{1}" -f $n,$lines[$n-1]) } }

Write-Output '===== 1) TUNNEL PID LIFECYCLE ====='
$lines | Select-String -Pattern 'ENSURE_TUNNEL spawned|ENSURE_TUNNEL ok|ENSURE_TUNNEL reused|killing orphan|had_bg=|TUNNEL_WAIT|bg_alive pid=|PROC_START|elevated_launch|fuser -k|pkill' |
  Select-Object -First 80 |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output '===== 2) WINDOW around first death: 140-195 ====='
Slice 140 195

Write-Output '===== 3) Who cleared ACTIVE_MOUNT before CLEAR_MOUNT? (160-240) ====='
$lines[159..239] | ForEach-Object -Begin {$n=160} -Process {
  if ($_ -match 'ACTIVE_MOUNT|PUSH_CONF|CLEAR_MOUNT|TUNNEL_|session|WRITE|conf') {
    Write-Output ("{0}|{1}" -f $n, $_)
  }
  $n++
}

Write-Output '===== 4) TUNNEL up=False WITH banner present (race evidence) ====='
for ($n=1; $n -le $lines.Count; $n++) {
  if ($lines[$n-1] -match 'TUNNEL up=False' -and $lines[$n-1] -match 'banner=SSH') {
    Write-Output ("HIT_L{0}|{1}" -f $n, $lines[$n-1])
    # show 15 lines before
    for ($k=[Math]::Max(1,$n-15); $k -le $n; $k++) { Write-Output ("  ctx {0}|{1}" -f $k, $lines[$k-1].Trim()) }
  }
}

Write-Output '===== 5) All TUNNEL up= lines in first 600 ====='
for ($n=1; $n -le [Math]::Min(600,$lines.Count); $n++) {
  if ($lines[$n-1] -match 'TUNNEL up=|TUNNEL_UP port=') {
    Write-Output ("{0}|{1}" -f $n, $lines[$n-1].Trim())
  }
}

Write-Output '===== 6) Cursor process / elevated interaction near death ====='
$lines | Select-String -Pattern 'elevated|PROC_START|LAUNCH_|profile_procs count|Cursor.exe' |
  Where-Object { $_.LineNumber -ge 130 -and $_.LineNumber -le 200 } |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output '===== 7) Recovery gen / editor_opened flags ====='
$lines | Select-String -Pattern 'RECOVERY_|editor_opened|post_recovery|force_auth|skip_editor|skip_launch' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output '===== 8) Later TUNNEL_DOWN after 17:12? ====='
$lines | Select-String -Pattern 'TUNNEL_DOWN|SESSION_STATUS=BROKEN|SESSION_STATUS=OK|connection dropped|RECOVERY_BEGIN' |
  ForEach-Object { "{0}|{1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Output 'DONE_ROOT'
