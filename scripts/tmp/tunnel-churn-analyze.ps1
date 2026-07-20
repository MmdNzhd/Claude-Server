$ErrorActionPreference='Continue'
function Analyze-Log([string]$Path, [string]$Label) {
  if (-not (Test-Path $Path)) { Write-Output "MISSING $Label $Path"; return }
  $lines = Get-Content $Path
  $size = (Get-Item $Path).Length
  Write-Output ""
  Write-Output "======== $Label ========"
  Write-Output ("file=$Path size=$size lines=$($lines.Count)")

  $patterns = [ordered]@{
    'session_start' = 'session start v'
    'session_end' = 'session end'
    'TUNNEL_DROP' = 'TUNNEL_DROP'
    'TUNNEL_SYNC soft_fail' = 'TUNNEL_SYNC soft_fail'
    'TUNNEL_SYNC ok=0|tunnel_down' = 'TUNNEL_SYNC.*(ok=0|tunnel_down|reason=tunnel_down)'
    'ENSURE_TUNNEL' = 'ENSURE_TUNNEL'
    'ORPHAN_TUNNEL' = 'ORPHAN_TUNNEL'
    'RECOVERY_BEGIN|Begin-ConnectRecovery' = 'RECOVERY_BEGIN|recovery begin|Begin-ConnectRecovery|SESSION: fallthrough_recover|auto_recovery'
    'manual recover key=r' = "SESSION_KEY.*action=r|DECISION: session_key.*=r|action=r "
    'user_quit' = 'reason=user_quit|action=q |keychar=q'
    'CLEAR_MOUNT' = 'CLEAR_MOUNT'
    'reconnect|relaunch tunnel' = 'reconnect|RECONNECT|tunnel.*relaunch|Initialize-SessionBgTunnel|start_session_tunnel|bg tunnel'
    'UPDATE applied' = 'applied_ok need_relaunch'
  }

  foreach ($k in $patterns.Keys) {
    $rx = $patterns[$k]
    $hits = @($lines | Select-String -Pattern $rx)
    Write-Output ("{0,5}  {1}" -f $hits.Count, $k)
  }

  Write-Output '--- TUNNEL_DROP sample (up to 15) ---'
  $lines | Select-String -Pattern 'TUNNEL_DROP|TUNNEL_SYNC soft_fail|fallthrough_recover|RECOVERY_BEGIN|session start|session end' |
    ForEach-Object { $_.Line.Trim() } | Select-Object -Last 40

  # Approximate reconnect cycles: session start count vs drop count
  $starts = @($lines | Select-String 'session start v').Count
  $drops = @($lines | Select-String 'TUNNEL_DROP').Count
  $soft = @($lines | Select-String 'TUNNEL_SYNC soft_fail').Count
  $recov = @($lines | Select-String 'RECOVERY_BEGIN|fallthrough_recover|Begin-ConnectRecovery').Count
  if ($starts -gt 0) {
    Write-Output ("approx drops_per_session_start={0:N2} soft_fails_per_start={1:N2} recovery_per_start={2:N2}" -f ($drops/$starts), ($soft/$starts), ($recov/$starts))
  }
}

Analyze-Log 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log' 'FARZAD forensic copy'
# Also try any other day logs in tmp
Get-ChildItem 'D:\Smart\Claude-Code-Server\scripts\tmp' -Filter 'connect-*.log' -ErrorAction SilentlyContinue | ForEach-Object {
  Analyze-Log $_.FullName ("TMP " + $_.Name)
}
Get-ChildItem 'D:\Smart\Claude-Code-Server\scripts\tmp' -Filter '*connect*2026*.log' -ErrorAction SilentlyContinue | ForEach-Object {
  Analyze-Log $_.FullName ("TMP " + $_.Name)
}
