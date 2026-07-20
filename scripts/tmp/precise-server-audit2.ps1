$ErrorActionPreference = 'Continue'
function Probe([string]$Name,[string]$RemoteHost,[string]$User) {
  Write-Output "=== SERVER_$Name ==="
  $key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
  $args = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=accept-new','-o','ConnectionAttempts=1')
  if (Test-Path $key) { $args = @('-i',$key) + $args }
  $remoteCmd = 'echo version=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING); EL=/usr/local/share/claude-client/editor-launch.ps1; echo preserve=$(grep -c preserve_open_windows "$EL" 2>/dev/null || echo 0); echo pre_launch_force=$(grep -c pre_launch_agent_or_new_window "$EL" 2>/dev/null || echo 0); echo retry_no_kill=$(grep -c LAUNCH_RETRY_NO_KILL "$EL" 2>/dev/null || echo 0); echo force_calls=$(grep -Ec "Stop-CursorServerProfileTreeIfNeeded.*-Force" "$EL" 2>/dev/null || echo 0); echo stop_total=$(grep -c Stop-CursorServerProfileTreeIfNeeded "$EL" 2>/dev/null || echo 0)'
  $target = "${User}@${RemoteHost}"
  Write-Output "target=$target"
  try {
    $job = Start-Job -ScriptBlock {
      param($exe,$a,$t,$c)
      & $exe @a $t $c 2>&1
      Write-Output ("JOB_EXIT=" + $LASTEXITCODE)
    } -ArgumentList 'ssh',$args,$target,$remoteCmd
    if (Wait-Job $job -Timeout 15) {
      Receive-Job $job | ForEach-Object { "$_" }
    } else {
      Write-Output 'TIMEOUT_15s'
      Stop-Job $job -ErrorAction SilentlyContinue
      Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Output ("ERR=" + $_.Exception.Message)
  }
}
Probe 'SMART' '192.168.210.240' 'smart'
Probe 'SEPIDZ' '192.168.250.70' 'sepidz'
Write-Output '=== DONE ==='
