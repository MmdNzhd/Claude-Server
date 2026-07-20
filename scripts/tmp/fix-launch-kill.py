from pathlib import Path

path = Path(r"D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1")
text = path.read_text(encoding="utf-8-sig")
nl = "\r\n" if "\r\n" in text else "\n"

old_need = """    $needKill = ($EditorCmd -eq 'cursor') -and ($agentHome -or $useNewWindow) -and ($profileProcCount -gt 0)
    if ($needKill) {
        $swKill = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Stop-CursorServerProfileTreeIfNeeded -Reason 'pre_launch_agent_or_new_window' -Force
        $swKill.Stop()
        Write-LaunchPerfLog -Mark 'launch_kill_profile' -Ms $swKill.ElapsedMilliseconds
    }"""

new_need = """    # Never force-kill the ClaudeServerCursorProfile tree before launch.
    # Multiple remote projects share one profile -- killing the tree closes ALL Cursor windows.
    # Prefer --new-window (already set via $useNewWindow) and keep other projects open.
    if ($EditorCmd -eq 'cursor' -and ($agentHome -or $useNewWindow) -and ($profileProcCount -gt 0)) {
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=preserve_open_windows profile_count={0} agent_home={1} use_new_window={2}" -f $profileProcCount, $agentHome, $useNewWindow) 'INFO'
        Write-LaunchPerfLog -Mark 'launch_kill_profile' -Ms 0 -Extra 'skipped=preserve_open_windows'
    }"""

if old_need not in text:
    raise SystemExit("needKill block not found")
text = text.replace(old_need, new_need, 1)

old_retry = """        if ($attempt -gt 1 -and $EditorCmd -eq 'cursor' -and (Get-CursorProfileProcesses).Count -gt 0) {
            $null = Stop-CursorServerProfileTreeIfNeeded -Reason "retry_before_$($strategy.Name)" -Force
        }"""

new_retry = """        if ($attempt -gt 1 -and $EditorCmd -eq 'cursor') {
            # Do not wipe the profile on strategy retry -- other open projects must stay alive.
            Write-EditorLaunchLog "LAUNCH_RETRY_NO_KILL: strategy=$($strategy.Name) preserving profile windows" 'DEBUG'
        }"""

if old_retry not in text:
    raise SystemExit("retry kill block not found")
text = text.replace(old_retry, new_retry, 1)

# Soften Stop-CursorServerProfileTreeIfNeeded docstring via comment near Force default path:
# Leave function available for emergency/manual use, but document it.
old_fn = """function Stop-CursorServerProfileTreeIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [switch]$Force
    )
    $procs = @(Get-CursorProfileProcesses)
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=0" 'DEBUG'
        return 0
    }
    if (-not $Force) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=$($procs.Count) force_not_set" 'DEBUG'
        return 0
    }
    Write-EditorLaunchLog "LAUNCH_KILL: reason=$Reason profile_count=$($procs.Count) elevated=$(Test-IsElevatedShell)" 'INFO'
    Stop-CursorServerProfileTree
    Start-Sleep -Milliseconds 400
    $remaining = @(Get-CursorProfileProcesses).Count
    Write-EditorLaunchLog "LAUNCH_KILL_DONE: remaining_profile_procs=$remaining" 'INFO'
    return $procs.Count
}"""

new_fn = """function Stop-CursorServerProfileTreeIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [switch]$Force
    )
    # WARNING: -Force kills EVERY Cursor process using ClaudeServerCursorProfile
    # (all open remote projects). Launch-RemoteEditor must NOT call this with -Force.
    # Kept for rare operator/manual recovery only.
    $procs = @(Get-CursorProfileProcesses)
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=0" 'DEBUG'
        return 0
    }
    if (-not $Force) {
        Write-EditorLaunchLog "LAUNCH_KILL_SKIP: reason=$Reason profile_count=$($procs.Count) force_not_set" 'DEBUG'
        return 0
    }
    Write-EditorLaunchLog "LAUNCH_KILL: reason=$Reason profile_count=$($procs.Count) elevated=$(Test-IsElevatedShell) WARNING=closes_all_profile_windows" 'WARN'
    Stop-CursorServerProfileTree
    Start-Sleep -Milliseconds 400
    $remaining = @(Get-CursorProfileProcesses).Count
    Write-EditorLaunchLog "LAUNCH_KILL_DONE: remaining_profile_procs=$remaining" 'INFO'
    return $procs.Count
}"""

if old_fn not in text:
    raise SystemExit("Stop-CursorServerProfileTreeIfNeeded block not found")
text = text.replace(old_fn, new_fn, 1)

path.write_text(text, encoding="utf-8", newline="")
print("patched editor-launch.ps1")
