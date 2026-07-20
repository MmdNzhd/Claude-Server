from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1")
c = p.read_text(encoding="utf-8")
old = """            # Disconnect (Q)
            $script:EditorSeenOpen = $false
            $editorOpened = $false
            Write-Host ""
            Write-Host "    Disconnecting..." -ForegroundColor DarkGray
            Write-ConnectLog "SESSION: disconnect project=$($go.Id)"
            Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
            $alreadyDown = $true
            Write-Host "    Laptop folder restored." -ForegroundColor Green
            break sessionLoop
"""
new = """            if ($action -eq 'q') {
                # Explicit quit only (never fall through from ignored Persian keys / empty action).
                $script:EditorSeenOpen = $false
                $editorOpened = $false
                Write-Host ""
                Write-Host "    Disconnecting..." -ForegroundColor DarkGray
                Write-ConnectLog "SESSION: disconnect project=$($go.Id) reason=user_quit"
                Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -Reason 'user_quit'
                Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
                $alreadyDown = $true
                Write-Host "    Laptop folder restored." -ForegroundColor Green
                break sessionLoop
            }

            if (-not $tunnelSyncOk) {
                # Tunnel drop with no usable key — recover (same as action=r auto path).
                Write-ConnectLog 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'
                $action = 'r'
                $skipRecoveryClear = [bool]($editorOpened -or $script:EditorSeenOpen)
                Begin-ConnectRecovery -Trigger 'auto' -ProjectId $go.Id -EditorWasOpen $skipRecoveryClear
                if ($skipRecoveryClear) {
                    Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_open' 'WARN'
                    $alreadyDown = $false
                } else {
                    Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop -Reason 'auto_recovery'
                    Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
                    $alreadyDown = $true
                }
                $script:LaptopSshVerified = $false
                continue sessionLoop
            }

            Write-ConnectLog ("SESSION: ignore_empty_action gotKey={0} tunnel={1}" -f $gotKey, $tunnelSyncOk) 'WARN'
            continue sessionLoop
"""
if old not in c:
    raise SystemExit('disconnect block not found')
c = c.replace(old, new, 1)
# also tag recovery clear
c = c.replace(
    "Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop\n                    Stop-SessionTunnelCleanup",
    "Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop -Reason 'auto_recovery'\n                    Stop-SessionTunnelCleanup",
    1,
)
p.write_text(c, encoding="utf-8", newline="\n")
print("OK disconnect guard")
