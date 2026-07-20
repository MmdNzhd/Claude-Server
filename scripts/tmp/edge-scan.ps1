$ErrorActionPreference = 'Continue'
function ShowHits([string]$Path, [string[]]$Pats) {
    Write-Host "`n==== $Path ===="
    foreach ($pat in $Pats) {
        Select-String -Path $Path -Pattern $pat | ForEach-Object {
            $ln = $_.Line.Trim()
            if ($ln.Length -gt 140) { $ln = $ln.Substring(0, 140) }
            Write-Host ("{0}:{1}" -f $_.LineNumber, $ln)
        }
    }
}
ShowHits 'scripts/client/windows/connect.ps1' @(
    'RECOVERY_SKIP', 'FINALLY_KEEP', "action -eq 'r'", 'alreadyDown', 'editorOpened',
    'Milliseconds 800', 'Clear-SessionMount', 'Stop-SessionTunnelCleanup', 'Begin-ConnectRecovery'
)
ShowHits 'scripts/client/git-mode.ps1' @(
    'TunnelSyncFailCount', 'no_proc_tcp_open', 'Remove-LocalOrphanTunnel', 'SessionBgTunnel',
    'LastEnsureSpawn', 'ENSURE_TUNNEL soft', 'function Sync-SessionTunnelProcess',
    'function Ensure-SessionTunnel', 'function Push-ServerConnectConf', 'self-heal'
)
ShowHits 'scripts/client/mac/connect.sh' @('RECOVERY_SKIP', 'FINALLY_KEEP', 'clear_session_mount', 'stop_session_tunnel')
ShowHits 'scripts/client/git-mode.sh' @(
    'ensure_session_tunnel', 'sync_session_tunnel', 'TUNNEL_SYNC_FAIL', 'banner_miss_tcp',
    'push_server_connect_conf', 'self-heal', 'tunnel_port_tcp_open'
)

Write-Host "`n==== EXTRACT Win recovery block ===="
$c = Get-Content 'scripts/client/windows/connect.ps1'
$start = ($c | Select-String -Pattern "if \(\`$action -eq 'r'\)" | Select-Object -First 1).LineNumber
if ($start) { for ($i=$start-1; $i -lt [Math]::Min($start+80,$c.Count); $i++) { '{0,5}|{1}' -f ($i+1), $c[$i] } }

Write-Host "`n==== EXTRACT Win finally ===="
$start = ($c | Select-String -Pattern '\} finally \{' | Select-Object -Last 1).LineNumber
if ($start) { for ($i=$start-1; $i -lt [Math]::Min($start+40,$c.Count); $i++) { '{0,5}|{1}' -f ($i+1), $c[$i] } }

Write-Host "`n==== EXTRACT Sync-SessionTunnelProcess ===="
$g = Get-Content 'scripts/client/git-mode.ps1'
$start = ($g | Select-String -Pattern '^function Sync-SessionTunnelProcess' | Select-Object -First 1).LineNumber
if ($start) { for ($i=$start-1; $i -lt [Math]::Min($start+160,$g.Count); $i++) { '{0,5}|{1}' -f ($i+1), $g[$i]; if ($i -gt $start -and $g[$i] -match '^function ') { break } } }

Write-Host "`n==== EXTRACT Ensure-SessionTunnel ===="
$start = ($g | Select-String -Pattern '^function Ensure-SessionTunnel' | Select-Object -First 1).LineNumber
if ($start) { for ($i=$start-1; $i -lt [Math]::Min($start+120,$g.Count); $i++) { '{0,5}|{1}' -f ($i+1), $g[$i]; if ($i -gt $start -and $g[$i] -match '^function ') { break } } }

Write-Host "`n==== EXTRACT Remove-LocalOrphanTunnel ===="
$start = ($g | Select-String -Pattern '^function Remove-LocalOrphanTunnel' | Select-Object -First 1).LineNumber
if ($start) { for ($i=$start-1; $i -lt [Math]::Min($start+40,$g.Count); $i++) { '{0,5}|{1}' -f ($i+1), $g[$i]; if ($i -gt $start -and $g[$i] -match '^function ') { break } } }
