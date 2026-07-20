$ErrorActionPreference='Stop'

# Read current Sync soft_fail no_proc and Ensure reuse sections for patching
$gPath = (Resolve-Path 'scripts/client/git-mode.ps1').Path
$cPath = (Resolve-Path 'scripts/client/windows/connect.ps1').Path
$g = [IO.File]::ReadAllText($gPath)
$c = [IO.File]::ReadAllText($cPath)

# 1) Sticky editorOpened: don't clear to false on transient miss in idle loop
# Find the idle editor check block
$oldIdle = @'
                if ($EditorCmd -eq 'cursor' -and ((Get-Date) - $lastEditorCheckAt -gt [TimeSpan]::FromSeconds(2))) {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $editorOpened = $onFolderNow
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } else { 'closed' }
                    $lastEditorCheckAt = Get-Date
'@
$newIdle = @'
                if ($EditorCmd -eq 'cursor' -and ((Get-Date) - $lastEditorCheckAt -gt [TimeSpan]::FromSeconds(2))) {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    # Sticky: once seen on folder, transient detection misses must not authorize CLEAR_MOUNT.
                    if ($onFolderNow) { $editorOpened = $true; $script:EditorSeenOpen = $true }
                    elseif ($script:EditorSeenOpen) { $editorOpened = $true }
                    else { $editorOpened = $false }
                    $editorLabel = if ($onFolderNow -or ($script:EditorSeenOpen -and $windowOpen)) { $EditorName } elseif ($windowOpen) { 'agent' } elseif ($script:EditorSeenOpen) { 'sticky' } else { 'closed' }
                    $lastEditorCheckAt = Get-Date
'@
if (-not $c.Contains($oldIdle)) { throw 'idle editor block not found' }
$c = $c.Replace($oldIdle, $newIdle)

# Reset EditorSeenOpen at session start and on Q disconnect
if ($c -notmatch 'EditorSeenOpen') {
  # add init near editorOpened = false at session start - already replaced above uses script:EditorSeenOpen
}
# session start
$c = $c.Replace(
  "`$editorOpened = `$false`r`n    `$script:RecoveryGeneration = 0",
  "`$editorOpened = `$false`r`n    `$script:EditorSeenOpen = `$false`r`n    `$script:RecoveryGeneration = 0"
)
if ($c -notmatch 'EditorSeenOpen = \$false') {
  $c = $c.Replace(
    "`$editorOpened = `$false`n    `$script:RecoveryGeneration = 0",
    "`$editorOpened = `$false`n    `$script:EditorSeenOpen = `$false`n    `$script:RecoveryGeneration = 0"
  )
}

# On Q disconnect clear sticky
$oldQ = @'
            Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
            $alreadyDown = $true
            Write-Host "    Laptop folder restored." -ForegroundColor Green
            break sessionLoop
'@
$newQ = @'
            Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
            Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
            $alreadyDown = $true
            $script:EditorSeenOpen = $false
            $editorOpened = $false
            Write-Host "    Laptop folder restored." -ForegroundColor Green
            break sessionLoop
'@
if (-not $c.Contains($oldQ)) { throw 'Q disconnect block not found' }
$c = $c.Replace($oldQ, $newQ)

# Auto recovery: use sticky EditorSeenOpen too
$oldSkip = @'
                $skipRecoveryClear = [bool]$editorOpened
                if (Get-Command Test-RemoteEditorOnCorrectFolder -ErrorAction SilentlyContinue) {
                    try {
                        if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                            $skipRecoveryClear = $true
                        }
                    } catch {
                        Write-ConnectLog "RECOVERY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                    }
                }
'@
$newSkip = @'
                $skipRecoveryClear = [bool]($editorOpened -or $script:EditorSeenOpen)
                if (Get-Command Test-RemoteEditorOnCorrectFolder -ErrorAction SilentlyContinue) {
                    try {
                        if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                            $skipRecoveryClear = $true
                            $script:EditorSeenOpen = $true
                        }
                    } catch {
                        Write-ConnectLog "RECOVERY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                        # On check failure, prefer preserve if we previously saw editor open.
                        if ($script:EditorSeenOpen) { $skipRecoveryClear = $true }
                    }
                }
'@
if (-not $c.Contains($oldSkip)) { throw 'skipRecoveryClear block not found' }
$c = $c.Replace($oldSkip, $newSkip)

# finally: sticky
$oldFin = @'
            $keepTunnelForEditor = [bool]$editorOpened
            if (Get-Command Test-RemoteEditorOnCorrectFolder -ErrorAction SilentlyContinue) {
                try {
                    $keepTunnelForEditor = [bool](Test-RemoteEditorOnCorrectFolder `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                } catch {
                    Write-ConnectLog "FINALLY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                }
            }
'@
$newFin = @'
            $keepTunnelForEditor = [bool]($editorOpened -or $script:EditorSeenOpen)
            if (Get-Command Test-RemoteEditorOnCorrectFolder -ErrorAction SilentlyContinue) {
                try {
                    if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                        $keepTunnelForEditor = $true
                        $script:EditorSeenOpen = $true
                    }
                } catch {
                    Write-ConnectLog "FINALLY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                    if ($script:EditorSeenOpen) { $keepTunnelForEditor = $true }
                }
            }
'@
if (-not $c.Contains($oldFin)) { throw 'finally editor block not found' }
$c = $c.Replace($oldFin, $newFin)

# Split alreadyDown semantics for skip-clear recovery:
# When skipRecoveryClear, set MountCleared=$false TunnelStopped=$false explicitly via alreadyDown=false (already done).
# Add remount path: after skip clear, force mount check on next loop by not setting alreadyDown.
# Also call Initialize-SessionBgTunnel immediately on skip path so tunnel is re-ensured before continue.
$oldSkipPath = @'
                if ($skipRecoveryClear) {
                    $editorOpened = $true
                    Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_open' 'WARN'
                    Write-ConnectLog 'TUNNEL: recovering session (preserve mount, re-ensure tunnel)' 'WARN'
                    $alreadyDown = $false
                } else {
'@
$newSkipPath = @'
                if ($skipRecoveryClear) {
                    $editorOpened = $true
                    $script:EditorSeenOpen = $true
                    Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_open' 'WARN'
                    Write-ConnectLog 'TUNNEL: recovering session (preserve mount, re-ensure tunnel)' 'WARN'
                    $alreadyDown = $false
                    # Re-ensure reverse tunnel now so Cursor/SSHFS do not sit on a dead -R until next loop steps.
                    try {
                        $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet
                        if ($script:SessionBgTunnel) { $bgTunnel = $script:SessionBgTunnel }
                    } catch {
                        Write-ConnectLog "RECOVERY_REENSURE_FAILED error=$($_.Exception.Message)" 'WARN'
                    }
                } else {
'@
if (-not $c.Contains($oldSkipPath)) { throw 'skip path block not found' }
$c = $c.Replace($oldSkipPath, $newSkipPath)

[IO.File]::WriteAllText($cPath, $c)
Write-Host 'OK connect.ps1 sticky editor + reensure'

# 2) Bound TCP-open soft_fail: after N soft fails with no process, still debounce but require reattach or eventually fail
# In Sync-SessionTunnelProcess no_proc_tcp_open path, increment a soft counter; after 10 soft fails (~with probes) force harder check.
# Simpler: add TunnelSoftFailCount, reset on real success; if soft fails >= 6 without successful banner, treat as miss toward debounce.

if ($g -notmatch 'TunnelSoftFailCount') {
  $g = $g.Replace(
    '$script:TunnelSyncFailCount = 0',
    "`$script:TunnelSyncFailCount = 0`r`n`$script:TunnelSoftFailCount = 0",
    1
  )
}

$oldSoft = @'
            Write-GitModeLog "TUNNEL_SYNC soft_fail port=$Port reason=no_proc_tcp_open" 'WARN'
'@
# Find fuller context around no_proc_tcp_open
if ($g -notmatch 'no_proc_tcp_open') { throw 'no_proc_tcp_open missing' }

# Patch Ensure recent spawn to key by port
# Search LastEnsureSpawn
Write-Host '--- LastEnsure / spawn guard ---'
Select-String -Path $gPath -Pattern 'LastEnsure|SpawnAt|spawn guard|within' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }

[IO.File]::WriteAllText($gPath, $g)  # interim if soft counter added
Write-Host 'partial git-mode written'
