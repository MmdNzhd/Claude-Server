$ErrorActionPreference='Continue'
$files = @(
  '/usr/local/share/claude-client/connect.ps1',
  '/usr/local/share/claude-client/git-mode.ps1',
  '/usr/local/share/claude-client/editor-launch.ps1',
  '/usr/local/share/claude-client/connect-ui.ps1'
)
$patterns = @(
  'RECOVERY_SKIP_CLEAR_MOUNT',
  'FINALLY_KEEP_TUNNEL',
  'EditorSeenOpen',
  'TunnelSoftFailCount',
  'no_proc_tcp_open',
  'CLEAR_MOUNT',
  'Push-ServerConnectConf',
  'AM=""'
)
foreach ($p in $patterns) {
  Write-Output ("=== PAT $p ===")
  foreach ($f in $files) {
    $cmd = "grep -nF '$p' $f 2>/dev/null | head -5"
    $out = ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 $cmd
    if ($out) { Write-Output "FILE $f"; Write-Output $out }
  }
}
Write-Output '=== VERSION FILES LOCAL ==='
Get-Content D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt -ErrorAction SilentlyContinue
Get-Content D:\Smart\Claude-Code-Server\scripts\client\connect-version.txt -ErrorAction SilentlyContinue
Get-Content D:\Smart\Claude-Code-Server\connect-version.txt -ErrorAction SilentlyContinue
