$ErrorActionPreference = 'Stop'
$path = (Resolve-Path 'scripts\client\windows\connect.ps1').Path
$utf8 = New-Object System.Text.UTF8Encoding $false
$c = [IO.File]::ReadAllText($path, $utf8)
$orig = $c
$n = 0

function Apply-Once([string]$label, [string]$old, [string]$new) {
    if ($script:c.Contains($new.Trim())) {
        Write-Host "SKIP already:$label"
        return
    }
    if (-not $script:c.Contains($old)) {
        Write-Host "MISS old:$label"
        return
    }
    $script:c = $script:c.Replace($old, $new)
    $script:n++
    Write-Host "APPLIED:$label"
}

# --- 1) Stage 1b: CR strip before ToBase64String ---
$old1 = @'
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemoteCmd))
'@
$new1 = @'
    # Bash remote payloads must be LF-only: Windows CRLF in here-docs/for-loops breaks `bash -c`.
    $RemoteCmd = $RemoteCmd -replace "`r`n", "`n" -replace "`r", "`n"
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemoteCmd))
'@
Apply-Once 'ssh-cr-strip' $old1 $new1

# --- 2) Stage 5: MountOk reassert before RECOVERY_END ---
$old2 = @'
    if (-not $script:PostTunnelRecovery) { return }
    $elapsed = 0
    if ($script:RecoveryStartedAt) {
        $elapsed = [int]((Get-Date) - $script:RecoveryStartedAt).TotalMilliseconds
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "RECOVERY_END elapsed_ms=$elapsed mount_ok=$MountOk gen=$($script:RecoveryGeneration) auth=$AuthDetail"
    }
'@
$new2 = @'
    if (-not $script:PostTunnelRecovery) { return }
    $elapsed = 0
    if ($script:RecoveryStartedAt) {
        $elapsed = [int]((Get-Date) - $script:RecoveryStartedAt).TotalMilliseconds
    }
    # Re-probe live mount before terminal RECOVERY_END (claimed MountOk can race SSHFS down).
    if ($MountOk -and $ProjectId -and (Get-Command Test-ProjectMountHealthy -ErrorAction SilentlyContinue)) {
        $liveMount = $false
        try { $liveMount = [bool](Test-ProjectMountHealthy -ProjectId $ProjectId) } catch { $liveMount = $false }
        if (-not $liveMount) { $MountOk = $false }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "RECOVERY_MOUNTOK_REASSERT live=$liveMount mount_ok=$MountOk project=$ProjectId" 'INFO'
        }
    } elseif ($MountOk -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {
        Write-ConnectLog "RECOVERY_MOUNTOK_REASSERT live=unknown mount_ok=$MountOk project=$ProjectId" 'DEBUG'
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "RECOVERY_END elapsed_ms=$elapsed mount_ok=$MountOk gen=$($script:RecoveryGeneration) auth=$AuthDetail"
    }
'@
Apply-Once 'mountok-reassert' $old2 $new2

# --- 3) Stage 4: auto-recovery uses presence API ---
$old3 = @'
                $skipRecoveryClear = $false
                if (Get-Command Test-RemoteEditorOnCorrectFolder -ErrorAction SilentlyContinue) {
                    try {
                        if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                            $skipRecoveryClear = $true
                            $editorOpened = $true
                            $script:EditorSeenOpen = $true
                        } else {
                            $windowStillOpen = $false
                            if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
                                $windowStillOpen = [bool](Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                            }
                            if (-not $windowStillOpen) {
                                if ($script:EditorSeenOpen) {
                                    Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=auto_recovery' 'INFO'
                                }
                                $script:EditorSeenOpen = $false
                                $editorOpened = $false
                            } else {
                                # Window open but not on folder: preserve mount, do not fake on-folder.
                                $skipRecoveryClear = $true
                                $editorOpened = $false
                                Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_window_open_not_on_folder' 'INFO'
                            }
                        }
                    } catch {
                        # Transient CIM failure: keep prior sticky only if still marked; do not force editorOpened.
                        if ($script:EditorSeenOpen) {
                            $skipRecoveryClear = $true
                            Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_check_failed_sticky' 'WARN'
                        }
                        Write-ConnectLog "RECOVERY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                    }
                } elseif ($editorOpened) {
                    $skipRecoveryClear = $true
                }
'@
$new3 = @'
                $skipRecoveryClear = $false
                # Stage 4: presence API (WindowOpen without requiring on-folder). Do NOT use
                # Test-RemoteEditorWindowOpen here - that helper is auth-gated to on-folder only.
                if (Get-Command Get-RemoteEditorSessionPresence -ErrorAction SilentlyContinue) {
                    try {
                        $presence = Get-RemoteEditorSessionPresence -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                        if ($presence.OnFolder) {
                            $skipRecoveryClear = $true
                            $editorOpened = $true
                            $script:EditorSeenOpen = $true
                        } elseif ($presence.WindowOpen) {
                            # Window open but not on folder: preserve mount, do not fake on-folder.
                            $skipRecoveryClear = $true
                            $editorOpened = $false
                            Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_window_open_not_on_folder' 'INFO'
                        } else {
                            if ($script:EditorSeenOpen) {
                                Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=auto_recovery' 'INFO'
                            }
                            $script:EditorSeenOpen = $false
                            $editorOpened = $false
                        }
                    } catch {
                        # Transient CIM failure: keep prior sticky only if still marked; do not force editorOpened.
                        if ($script:EditorSeenOpen) {
                            $skipRecoveryClear = $true
                            Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_check_failed_sticky' 'WARN'
                        }
                        Write-ConnectLog "RECOVERY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                    }
                } elseif ($editorOpened) {
                    $skipRecoveryClear = $true
                }
'@
Apply-Once 'recovery-presence' $old3 $new3

# --- 4) Stage 6: auto_relaunch Settings gate ---
$old4 = @'
                            if ($script:AgentHomeStreak -ge 3 -and -not $script:AutoRelaunchAttempted) {
                                $script:AutoRelaunchAttempted = $true
                                Write-ConnectLog "SESSION: auto_relaunch agent_home_streak=$($script:AgentHomeStreak) - reopening project folder" 'WARN'
                                Warn 'Cursor drifted to Agent/home - reopening project folder automatically...'
                                if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                                    if ($onFolderNow) {
                                        $editorOpened = $true
                                        $script:EditorSeenOpen = $true
                                        $script:AgentHomeStreak = 0
                                    }
                                }
                            }
'@
$new4 = @'
                            if ($script:AgentHomeStreak -ge 3 -and -not $script:AutoRelaunchAttempted) {
                                # Settings-focused Cursor lacks folder-uri titles - do not auto_relaunch.
                                $settingsFocused = $false
                                try {
                                    if (Get-Command Get-CursorMainProfileProcesses -ErrorAction SilentlyContinue) {
                                        foreach ($p in @(Get-CursorMainProfileProcesses)) {
                                            $title = ''
                                            try { $title = [string]$p.MainWindowTitle } catch { $title = '' }
                                            if ($title -match '(?i)settings') { $settingsFocused = $true; break }
                                        }
                                    }
                                } catch { $settingsFocused = $false }
                                if ($settingsFocused) {
                                    Write-ConnectLog 'SESSION: auto_relaunch_skip reason=cursor_settings' 'INFO'
                                } else {
                                    $script:AutoRelaunchAttempted = $true
                                    Write-ConnectLog "SESSION: auto_relaunch agent_home_streak=$($script:AgentHomeStreak) - reopening project folder" 'WARN'
                                    Warn 'Cursor drifted to Agent/home - reopening project folder automatically...'
                                    if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                                        $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                                        if ($onFolderNow) {
                                            $editorOpened = $true
                                            $script:EditorSeenOpen = $true
                                            $script:AgentHomeStreak = 0
                                        }
                                    }
                                }
                            }
'@
Apply-Once 'auto-relaunch-settings' $old4 $new4

# --- 5) Stage 6b: Smart hard-refuse path/IP ---
if ($c -notmatch 'claude-code-sepidz|Claude-Connect-Sepidz') {
    $old5 = @'
function Die($m) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "ERROR: $m" 'ERROR'
        Write-ConnectLog "FAIL DIE: $m" 'ERROR'
        if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    }
    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red
    if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) {
        Wait-ConnectExit -Reason 'require_fail' -Code 1
    } else {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 1
    }
}
'@
    $new5 = @'
function Die($m) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "ERROR: $m" 'ERROR'
        Write-ConnectLog "FAIL DIE: $m" 'ERROR'
        if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    }
    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red
    if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) {
        Wait-ConnectExit -Reason 'require_fail' -Code 1
    } else {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 1
    }
}
function Test-PathLooksSepidz([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    $n = $Dir.ToLowerInvariant()
    return ($n -match 'claude-code-sepidz') -or ($n -match 'claude-connect-sepidz')
}
# Smart package must never run from Sepidz folder names; Sepidz IP only under Sepidz tree.
try {
    $launchDir = if ($script:ConnectScriptDir) { $script:ConnectScriptDir } else { $PSScriptRoot }
    $sepidzPath = Test-PathLooksSepidz $launchDir
    if ($sepidzPath -and $ServerIP -ne '192.168.250.70') {
        Die 'REFUSE Smart/Sepidz contamination: Smart package under Sepidz path (claude-code-sepidz / Claude-Connect-Sepidz)'
    }
    $smartCanon = $false
    try {
        $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
        if ($launchDir -and (Test-Path -LiteralPath $canon)) {
            $a = [IO.Path]::GetFullPath($launchDir).TrimEnd('\', '/').ToLowerInvariant()
            $b = [IO.Path]::GetFullPath($canon).TrimEnd('\', '/').ToLowerInvariant()
            if ($a -eq $b -or $a.StartsWith($b + '\')) { $smartCanon = $true }
        }
    } catch {}
    if ($ServerIP -eq '192.168.250.70' -and (-not $sepidzPath -or $smartCanon)) {
        Die 'REFUSE Smart/Sepidz contamination: ServerIP 192.168.250.70 outside Sepidz tree (or Smart Claude-Connect path)'
    }
} catch {}
'@
    Apply-Once 'hard-refuse' $old5 $new5
} else {
    Write-Host 'SKIP already:hard-refuse-strings'
}

if ($c -eq $orig) { throw 'No patches applied' }

$tmp = $path + '.tmpfix'
[IO.File]::WriteAllText($tmp, $c, $utf8)
[IO.File]::Copy($tmp, $path, $true)
[IO.File]::Delete($tmp)

$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
Write-Host ("patches=$n parse_errs=" + $(if ($errs) { $errs.Count } else { 0 }))
if ($errs) { $errs | Select-Object -First 10 | ForEach-Object { Write-Host $_.ToString() }; throw 'parse failed' }
Write-Host 'OK'
