function Probe($label, $server) {
  Write-Host "=== $label ($server) ===" -ForegroundColor Cyan
  $cmd = @'
f=/usr/local/share/claude-client/editor-launch.ps1
v=/usr/local/share/claude-client/connect-version.txt
if [ ! -f "$f" ]; then echo MISSING_EDITOR_LAUNCH; exit 0; fi
echo VER=$(tr -d '\r\n' < "$v" 2>/dev/null)
echo PRESERVE=$(grep -c preserve_open_windows "$f" 2>/dev/null || echo 0)
echo FORCE_BAN=$(grep -c "pre_launch_agent_or_new_window" "$f" 2>/dev/null || echo 0)
echo RETRY_NO_KILL=$(grep -c LAUNCH_RETRY_NO_KILL "$f" 2>/dev/null || echo 0)
'@
  ssh -o BatchMode=yes -o ConnectTimeout=15 $server $cmd
}
Probe 'Smart' 'smart@192.168.210.240'
Probe 'Sepidz' 'sepidz@192.168.250.70'
