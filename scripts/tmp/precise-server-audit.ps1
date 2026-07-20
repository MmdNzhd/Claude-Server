$ErrorActionPreference = 'Continue'

function Probe-Server([string]$Name, [string]$RemoteHost, [string]$User) {
  Write-Output "=== SERVER_$Name ==="
  $key = "$env:USERPROFILE\.ssh\claude_laptop"
  $sshExe = 'ssh'
  $sshArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=accept-new')
  if (Test-Path $key) { $sshArgs += @('-i', $key) }
  $cmd = 'VER=/usr/local/share/claude-client/windows/connect-version.txt; EL=/usr/local/share/claude-client/windows/editor-launch.ps1; [ -f "$VER" ] || VER=/usr/local/share/claude-client/connect-version.txt; [ -f "$EL" ] || EL=/usr/local/share/claude-client/editor-launch.ps1; echo host=$(hostname); echo ver_file=$VER; if [ -f "$VER" ]; then echo version=$(tr -d ''\r\n'' < "$VER"); else echo version=MISSING; fi; echo el_file=$EL; if [ -f "$EL" ]; then echo preserve=$(grep -c preserve_open_windows "$EL" || true); echo pre_launch_force=$(grep -c pre_launch_agent_or_new_window "$EL" || true); echo retry_no_kill=$(grep -c LAUNCH_RETRY_NO_KILL "$EL" || true); echo force_calls=$(grep -Ec "Stop-CursorServerProfileTreeIfNeeded.*-Force" "$EL" || true); echo stop_total=$(grep -c Stop-CursorServerProfileTreeIfNeeded "$EL" || true); else echo el=MISSING; ls /usr/local/share/claude-client 2>/dev/null | head -20; fi'
  $target = "$User@$RemoteHost"
  $out = & $sshExe @sshArgs $target $cmd 2>&1
  Write-Output ("exit=" + $LASTEXITCODE)
  Write-Output ($out | ForEach-Object { "$_" })
}

Probe-Server -Name 'SMART' -RemoteHost '192.168.210.240' -User 'smart'
Probe-Server -Name 'SEPIDZ' -RemoteHost '192.168.250.70' -User 'sepidz'
