# -*- coding: utf-8 -*-
from pathlib import Path
import re

ROOT = Path(r"D:\Smart\Claude-Code-Server")
TARGET = "20260721.45"

el = ROOT / "scripts/client/editor-launch.ps1"
t = el.read_text(encoding="utf-8")

old = '''        Initialize-CursorServerProfile
        $script:CursorProxyNeedsRelaunch = $false
        if ($script:SocksProxyPort) {
            # Cursor 3.9.x always-local-singleton ignores proxy until full process restart.
            # If keys changed, soft-stop the server profile so the relaunch below picks up
            # settings + --proxy-server/--disable-http2 (Reload Window is NOT enough).
            try {
                $proxyChanged = [bool](Set-CursorProxySettings -SocksPort ([int]$script:SocksProxyPort))
                if ($proxyChanged) { $script:CursorProxyNeedsRelaunch = $true }
            } catch { Write-EditorLaunchLog "CURSOR_PROXY_SET_FAIL: $($_.Exception.Message)" 'WARN' }
        } else {
            try {
                $proxyCleared = [bool](Clear-CursorProxySettings)
                if ($proxyCleared) { $script:CursorProxyNeedsRelaunch = $true }
            } catch { Write-EditorLaunchLog "CURSOR_PROXY_CLEAR_FAIL: $($_.Exception.Message)" 'WARN' }
        }
    }

    $swEntry = [System.Diagnostics.Stopwatch]::StartNew()
    if ($KnownOnFolder -and -not $script:CursorProxyNeedsRelaunch) {
        $onFolder = $true
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms 0 -Extra 'result=True skipped=known_on_folder'
    } else {
        $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        $swEntry.Stop()
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms $swEntry.ElapsedMilliseconds -Extra "result=$onFolder"
    }
    if ($EditorCmd -eq 'cursor' -and $script:CursorProxyNeedsRelaunch) {
        $pc = @(Get-CursorProfileProcesses).Count
        if ($pc -gt 0) {
            Write-EditorLaunchLog ("LAUNCH_KILL: reason=proxy_settings_changed soft-stop profile_count={0} socks={1}" -f $pc, $script:SocksProxyPort) 'WARN'
            Stop-CursorServerProfileTree
            Start-Sleep -Milliseconds 800
            Clear-CursorProcessCache
        }
        $onFolder = $false
        $script:CursorProxyNeedsRelaunch = $false
    }

    $swAgent = [System.Diagnostics.Stopwatch]::StartNew()
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $swAgent.Stop()
    Write-LaunchPerfLog -Mark 'entry_agent_home' -Ms $swAgent.ElapsedMilliseconds -Extra "result=$agentHome"

    $swProfile = [System.Diagnostics.Stopwatch]::StartNew()
    $hasProfileWindow = if ($EditorCmd -eq 'cursor') { (Get-CursorMainProfileProcesses).Count -gt 0 } else { $false }
    $profileProcCount = if ($EditorCmd -eq 'cursor') { (Get-CursorProfileProcesses).Count } else { 0 }
    $swProfile.Stop()
    Write-LaunchPerfLog -Mark 'entry_profile_counts' -Ms $swProfile.ElapsedMilliseconds -Extra "profile_main=$hasProfileWindow profile_all=$profileProcCount"

    if ($AuthRelaunch -and $EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        Write-EditorLaunchLog ("LAUNCH_KILL: reason=auth_relaunch soft-stop profile_count={0}" -f $profileProcCount) 'WARN'
        Stop-CursorServerProfileTree
        Start-Sleep -Milliseconds 800
        Clear-CursorProcessCache
        $onFolder = $false
        $agentHome = $false
        $hasProfileWindow = $false
        $profileProcCount = 0
    }'''

new = '''        Initialize-CursorServerProfile
        # Write proxy keys to disk, but NEVER soft-stop ClaudeServerCursorProfile for proxy
        # changes. Many windows share one profile; killing the tree closes ALL of them.
        # New launches get --proxy-server/--disable-http2 via Get-CursorProxyLaunchArgs.
        if ($script:SocksProxyPort) {
            try {
                $proxyChanged = [bool](Set-CursorProxySettings -SocksPort ([int]$script:SocksProxyPort))
                if ($proxyChanged) {
                    Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} (no soft-stop)" -f $script:SocksProxyPort) 'INFO'
                }
            } catch { Write-EditorLaunchLog "CURSOR_PROXY_SET_FAIL: $($_.Exception.Message)" 'WARN' }
        } else {
            try {
                $proxyCleared = [bool](Clear-CursorProxySettings)
                if ($proxyCleared) {
                    Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: preserved_open_windows (no soft-stop)' 'INFO'
                }
            } catch { Write-EditorLaunchLog "CURSOR_PROXY_CLEAR_FAIL: $($_.Exception.Message)" 'WARN' }
        }
    }

    $swEntry = [System.Diagnostics.Stopwatch]::StartNew()
    if ($KnownOnFolder) {
        $onFolder = $true
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms 0 -Extra 'result=True skipped=known_on_folder'
    } else {
        $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        $swEntry.Stop()
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms $swEntry.ElapsedMilliseconds -Extra "result=$onFolder"
    }

    $swAgent = [System.Diagnostics.Stopwatch]::StartNew()
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $swAgent.Stop()
    Write-LaunchPerfLog -Mark 'entry_agent_home' -Ms $swAgent.ElapsedMilliseconds -Extra "result=$agentHome"

    $swProfile = [System.Diagnostics.Stopwatch]::StartNew()
    $hasProfileWindow = if ($EditorCmd -eq 'cursor') { (Get-CursorMainProfileProcesses).Count -gt 0 } else { $false }
    $profileProcCount = if ($EditorCmd -eq 'cursor') { (Get-CursorProfileProcesses).Count } else { 0 }
    $swProfile.Stop()
    Write-LaunchPerfLog -Mark 'entry_profile_counts' -Ms $swProfile.ElapsedMilliseconds -Extra "profile_main=$hasProfileWindow profile_all=$profileProcCount"

    # Auth soft-stop ONLY when at most one main window is open. Never wipe multi-window sessions.
    if ($AuthRelaunch -and $EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        $mainCount = @(Get-CursorMainProfileProcesses).Count
        if ($mainCount -le 1) {
            Write-EditorLaunchLog ("LAUNCH_KILL: reason=auth_relaunch soft-stop profile_count={0} main={1}" -f $profileProcCount, $mainCount) 'WARN'
            Stop-CursorServerProfileTree
            Start-Sleep -Milliseconds 800
            Clear-CursorProcessCache
            $onFolder = $false
            $agentHome = $false
            $hasProfileWindow = $false
            $profileProcCount = 0
        } else {
            Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=auth_relaunch_preserve_open_windows profile_count={0} main={1}" -f $profileProcCount, $mainCount) 'WARN'
        }
    }'''

if old not in t:
    raise SystemExit('Win proxy/auth block not found')
t = t.replace(old, new, 1)
el.write_text(t, encoding="utf-8", newline="\n")
print("OK editor-launch.ps1")

# Mac
em = ROOT / "scripts/client/editor-launch.sh"
mt = em.read_text(encoding="utf-8").replace("\r\n", "\n")

old_m = '''        _cursor_proxy_needs_relaunch=0
        if [ -n "${SOCKS_PROXY_PORT:-}" ]; then
            if set_cursor_proxy_settings "$SOCKS_PROXY_PORT"; then
                _cursor_proxy_needs_relaunch=1
            fi
        else
            if clear_cursor_proxy_settings; then
                _cursor_proxy_needs_relaunch=1
            fi
        fi

        # Chromium flags: Cursor 3.9.x always-local-singleton can ignore settings.json proxy.
        _proxy_args=()
        if [ -n "${SOCKS_PROXY_PORT:-}" ]; then
            _proxy_args=(--proxy-server="socks5://127.0.0.1:${SOCKS_PROXY_PORT}" --disable-http2)
        fi

        if [ "$known_on_folder" = "1" ] && [ "$_cursor_proxy_needs_relaunch" != "1" ]; then
            on_folder=1
        else
            remote_editor_on_correct_folder cursor "$alias" "$remote_path" && on_folder=1
        fi
        if [ "$_cursor_proxy_needs_relaunch" = "1" ]; then
            if [ "$(cursor_profile_main_count)" -gt 0 ]; then
                declare -F connect_log >/dev/null 2>&1 && connect_log "LAUNCH_KILL: reason=proxy_settings_changed soft-stop socks=${SOCKS_PROXY_PORT:-}" 'WARN'
                stop_cursor_profile_soft
                sleep 0.8
            fi
            on_folder=0
            _cursor_proxy_needs_relaunch=0
        fi
        remote_editor_in_agent_home "$alias" "$remote_path" && agent_home=1
        profile_main="$(cursor_profile_main_count)"

        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAUNCH_BEGIN editor=cursor on_folder=$on_folder agent_home=$agent_home profile_main=$profile_main auth_relaunch=${CURSOR_AUTH_RELAUNCH:-0}"
        fi

        _auth_relaunch_done=0
        if [ "${CURSOR_AUTH_RELAUNCH:-0}" = "1" ] && [ "$profile_main" -gt 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_KILL: auth_relaunch soft-stop'
            stop_cursor_profile_soft
            on_folder=0
            agent_home=0
            profile_main=0
            _auth_relaunch_done=1
        fi'''

new_m = '''        # Write proxy settings but NEVER soft-stop (preserves N open windows).
        if [ -n "${SOCKS_PROXY_PORT:-}" ]; then
            if set_cursor_proxy_settings "$SOCKS_PROXY_PORT"; then
                declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_SET: preserved_open_windows socks=${SOCKS_PROXY_PORT} (no soft-stop)" 'INFO'
            fi
        else
            if clear_cursor_proxy_settings; then
                declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR: preserved_open_windows (no soft-stop)' 'INFO'
            fi
        fi

        # Chromium flags: Cursor 3.9.x always-local-singleton can ignore settings.json proxy.
        _proxy_args=()
        if [ -n "${SOCKS_PROXY_PORT:-}" ]; then
            _proxy_args=(--proxy-server="socks5://127.0.0.1:${SOCKS_PROXY_PORT}" --disable-http2)
        fi

        if [ "$known_on_folder" = "1" ]; then
            on_folder=1
        else
            remote_editor_on_correct_folder cursor "$alias" "$remote_path" && on_folder=1
        fi
        remote_editor_in_agent_home "$alias" "$remote_path" && agent_home=1
        profile_main="$(cursor_profile_main_count)"

        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAUNCH_BEGIN editor=cursor on_folder=$on_folder agent_home=$agent_home profile_main=$profile_main auth_relaunch=${CURSOR_AUTH_RELAUNCH:-0}"
        fi

        # Auth soft-stop only when at most one main window is open.
        _auth_relaunch_done=0
        if [ "${CURSOR_AUTH_RELAUNCH:-0}" = "1" ] && [ "$profile_main" -gt 0 ]; then
            if [ "$profile_main" -le 1 ]; then
                declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_KILL: auth_relaunch soft-stop profile main=1'
                stop_cursor_profile_soft
                on_folder=0
                agent_home=0
                profile_main=0
                _auth_relaunch_done=1
            else
                declare -F connect_log >/dev/null 2>&1 && connect_log "LAUNCH_KILL_SKIP: reason=auth_relaunch_preserve_open_windows main=$profile_main" 'WARN'
            fi
        fi'''

if old_m not in mt:
    raise SystemExit('Mac proxy/auth block not found')
mt = mt.replace(old_m, new_m, 1)
em.write_text(mt, encoding="utf-8", newline="\n")
print("OK editor-launch.sh")

for rel in ["scripts/client/windows/connect-version.txt", "scripts/client/mac/connect-version.txt"]:
    (ROOT / rel).write_text(TARGET + "\n", encoding="utf-8", newline="\n")
for path, pat, repl in [
    (ROOT / "scripts/client/windows/connect.ps1", r"ConnectVersion = '20260721\.\d+'", f"ConnectVersion = '{TARGET}'"),
    (ROOT / "scripts/client/mac/connect.sh", r"CONNECT_VERSION='20260721\.\d+'", f"CONNECT_VERSION='{TARGET}'"),
]:
    tt = path.read_text(encoding="utf-8")
    tt2, n = re.subn(pat, repl, tt, count=1)
    if n != 1:
        raise SystemExit(f"bump fail {path}")
    path.write_text(tt2, encoding="utf-8", newline="\n")
print("DONE", TARGET)
