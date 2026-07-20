$ErrorActionPreference='Continue'
Write-Host "=== Mac/sh perf gaps ==="
$files = @(
  'scripts\client\connect-ui.sh',
  'scripts\client\git-mode.sh',
  'scripts\client\mac\connect.sh'
)
foreach ($f in $files) {
  foreach ($p in @('CLAUDE_CONNECT_PERF','PERF_LOG','TUNNEL_SYNC','last_tunnel','sleep 0.5','editor_check','SINGLE_INSTANCE','sync_offset','512')) {
    $n = (Select-String -Path $f -Pattern $p -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($n -gt 0) { Write-Host ("{0}: {1} x{2}" -f $f, $p, $n) }
  }
}
Write-Host "=== connect-ui.sh connect_log / sync ==="
Select-String -Path scripts\client\connect-ui.sh -Pattern 'connect_log|sync_connect|PERF|TRACE|DEBUG|INFO' |
  Select-Object -First 40 |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)) }

Write-Host "=== git-mode.sh TUNNEL_SYNC context ==="
Select-String -Path scripts\client\git-mode.sh -Pattern 'TUNNEL_SYNC|LastTunnel|tunnel_sync' -Context 2,2 |
  ForEach-Object { $_.Line.Trim() }
