$ErrorActionPreference='Continue'
function Dump-Matches($file, $patterns) {
  Write-Host "`n======== $file ========"
  $lines = Get-Content $file
  for ($i=0; $i -lt $lines.Count; $i++) {
    foreach ($p in $patterns) {
      if ($lines[$i] -match $p) {
        $a=[Math]::Max(0,$i-2); $b=[Math]::Min($lines.Count-1,$i+25)
        Write-Host ("--- hit line {0} / {1} ---" -f ($i+1), $p)
        for ($j=$a; $j -le $b; $j++) { '{0,5}|{1}' -f ($j+1), $lines[$j] }
        break
      }
    }
  }
}

Dump-Matches 'scripts/client/windows/connect.ps1' @(
  'RECOVERY_SKIP_CLEAR_MOUNT','FINALLY_KEEP_TUNNEL','action -eq ''r''','alreadyDown','editorOpened',
  'Start-Sleep -Milliseconds','tunnelSyncOk','Clear-SessionMount','Stop-SessionTunnelCleanup'
)
Dump-Matches 'scripts/client/git-mode.ps1' @(
  'function Sync-SessionTunnelProcess','no_proc_tcp_open','TunnelSyncFailCount','Remove-LocalOrphanTunnel',
  'function Ensure-SessionTunnel','SessionBgTunnel','LastEnsureSpawn','Push-ServerConnectConf','self-heal'
)
Dump-Matches 'scripts/client/mac/connect.sh' @(
  'RECOVERY_SKIP_CLEAR_MOUNT','FINALLY_KEEP_TUNNEL','clear_session_mount','stop_session_tunnel'
)
Dump-Matches 'scripts/client/git-mode.sh' @(
  'ensure_session_tunnel','sync_session_tunnel','no_ssh_proc|no_proc|tcp_open','TUNNEL_SYNC_FAIL',
  'push_server_connect_conf','self-heal'
)
