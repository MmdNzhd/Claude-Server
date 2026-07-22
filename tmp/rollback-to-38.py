# -*- coding: utf-8 -*-
"""Roll client back to 20260721.38 behavior. Does NOT deploy."""
from pathlib import Path
import re
import shutil

ROOT = Path(r"D:\Smart\Claude-Code-Server")
CC = Path(r"C:\Users\Smart\Desktop\Claude-Connect")
TARGET = "20260721.38"

def replace_once(t, old, new, label):
    if old not in t:
        raise SystemExit(f"NOT FOUND: {label}")
    return t.replace(old, new, 1)

# ===== editor-launch.ps1 =====
el = ROOT / "scripts/client/editor-launch.ps1"
et = el.read_text(encoding="utf-8")

et2, n = re.subn(
    r"\nfunction Get-RunningCursorProxySocksPort \{.*?\n\}\n\n(?=function Set-CursorProxySettings)",
    "\n",
    et,
    count=1,
    flags=re.S,
)
if n != 1:
    raise SystemExit(f"EL remove RunningCli n={n}")
et = et2
print("EL: removed Get-RunningCursorProxySocksPort")

old_proxy = """        # Write proxy keys to disk, but NEVER soft-stop ClaudeServerCursorProfile for proxy
        # changes. Many windows share one profile (10+ Remote-SSH projects); killing the tree
        # closes all of them. New launches get --proxy-server/--disable-http2 via
        # Get-CursorProxyLaunchArgs; already-open windows keep Remote-SSH alive.
        if ($script:SocksProxyPort) {
            try {
                $socksForSettings = [int]$script:SocksProxyPort
                $runningCli = Get-RunningCursorProxySocksPort
                if ($null -ne $runningCli -and [int]$runningCli -gt 0 -and [int]$runningCli -ne $socksForSettings) {
                    Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_running_cli socks={0} session={1}" -f $runningCli, $socksForSettings) 'INFO'
                    $socksForSettings = [int]$runningCli
                }
                $proxyChanged = [bool](Set-CursorProxySettings -SocksPort $socksForSettings)
                if ($proxyChanged) {
                    Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} (no soft-stop)" -f $socksForSettings) 'INFO'
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
    }"""

new_proxy = """        $script:CursorProxyNeedsRelaunch = $false
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
    }"""

et = replace_once(et, old_proxy, new_proxy, "EL proxy block")
print("EL: restored .38 proxy soft-stop")

old_auth = """    # Auth just merged to disk. Soft-stop ONLY when at most one main Cursor window
    # is open on the server profile. Never close a multi-window session (10 projects).
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
    }"""

new_auth = """    if ($AuthRelaunch -and $EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        Write-EditorLaunchLog ("LAUNCH_KILL: reason=auth_relaunch soft-stop profile_count={0}" -f $profileProcCount) 'WARN'
        Stop-CursorServerProfileTree
        Start-Sleep -Milliseconds 800
        Clear-CursorProcessCache
        $onFolder = $false
        $agentHome = $false
        $hasProfileWindow = $false
        $profileProcCount = 0
    }"""

et = replace_once(et, old_auth, new_auth, "EL auth")
print("EL: restored .38 auth soft-stop")
el.write_text(et, encoding="utf-8", newline="\n")

# ===== git-mode.ps1 =====
gm = ROOT / "scripts/client/git-mode.ps1"
gt = gm.read_text(encoding="utf-8")

old_state = """function Get-TunnelProxyLegState {
    # Classify reverse-tunnel ssh cmdline + local listen for the xray proxy leg.
    # ok          = correct -L and local socks port is accepting
    # listen_down = cmdline has -L but local port not listening — must reseed
    # legacy_D    = old ssh -D (office-IP egress) — must reseed
    # missing     = no -L / -D for our socks port — must reseed when xray is up
    # unknown     = process gone / unreadable — reseed when xray is up (fail closed)
    param([Parameter(Mandatory)][int]$TunnelPid)
    $socksCandidate = Get-SocksProxyPort
    $xrayPort = [int]$script:XrayServerSocksPort
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$TunnelPid" -ErrorAction Stop
        $cmd = [string]$cim.CommandLine
        if (-not $cmd) { return 'unknown' }
        $fwdPat = "-L\\s+127\\.0\\.0\\.1:${socksCandidate}:127\\.0\\.0\\.1:${xrayPort}"
        if ($cmd -match $fwdPat) {
            $localOk = $false
            try {
                $localOk = [bool](Test-NetConnection -ComputerName 127.0.0.1 -Port $socksCandidate -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction SilentlyContinue)
            } catch { $localOk = $false }
            if ($localOk) { return 'ok' }
            return 'listen_down'
        }
        if ($cmd -match "-D\\s+127\\.0\\.0\\.1:${socksCandidate}\\b") { return 'legacy_D' }
        return 'missing'
    } catch {
        return 'unknown'
    }
}"""

new_state = """function Get-TunnelProxyLegState {
    # Classify reverse-tunnel ssh cmdline for the xray proxy leg.
    # ok       = correct -L to server xray
    # legacy_D = old ssh -D (office-IP egress) — must reseed
    # missing  = no -L / -D for our socks port — must reseed when xray is up
    # unknown  = process gone / unreadable
    param([Parameter(Mandatory)][int]$TunnelPid)
    $socksCandidate = Get-SocksProxyPort
    $xrayPort = [int]$script:XrayServerSocksPort
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$TunnelPid" -ErrorAction Stop
        $cmd = [string]$cim.CommandLine
        if (-not $cmd) { return 'unknown' }
        $fwdPat = "-L\\s+127\\.0\\.0\\.1:${socksCandidate}:127\\.0\\.0\\.1:${xrayPort}"
        if ($cmd -match $fwdPat) { return 'ok' }
        if ($cmd -match "-D\\s+127\\.0\\.0\\.1:${socksCandidate}\\b") { return 'legacy_D' }
        return 'missing'
    } catch {
        return 'unknown'
    }
}"""

gt = replace_once(gt, old_state, new_state, "GM state")
print("GM: state .38")

old_reseed = """    $state = Get-TunnelProxyLegState -TunnelPid $TunnelPid
    if ($state -eq 'ok') { return $false }
    # unknown / listen_down / legacy_D / missing → reseed (fail closed while xray is up)
    Write-GitModeLog "ENSURE_TUNNEL reseed_needed reason=$state pid=$TunnelPid socks=$(Get-SocksProxyPort)" 'WARN'
    return $true
}"""

new_reseed = """    $state = Get-TunnelProxyLegState -TunnelPid $TunnelPid
    if ($state -eq 'ok') { return $false }
    if ($state -eq 'unknown') { return $false }
    Write-GitModeLog "ENSURE_TUNNEL reseed_needed reason=$state pid=$TunnelPid socks=$(Get-SocksProxyPort)" 'WARN'
    return $true
}"""

gt = replace_once(gt, old_reseed, new_reseed, "GM reseed")
print("GM: reseed .38")

old_wto = """    Write-GitModeLog "ENSURE_TUNNEL ok=0 reason=wait_timeout pid=$($BgTunnel.Value.Id)" 'WARN'
    $script:SocksProxyPort = $null
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {"""
new_wto = """    Write-GitModeLog "ENSURE_TUNNEL ok=0 reason=wait_timeout pid=$($BgTunnel.Value.Id)" 'WARN'
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {"""
if old_wto in gt:
    gt = replace_once(gt, old_wto, new_wto, "GM wto")
    print("GM: removed wait_timeout Socks clear")
else:
    print("GM: wait_timeout Socks clear already absent")

gm.write_text(gt, encoding="utf-8", newline="\n")

# ===== git-mode.sh =====
gs = ROOT / "scripts/client/git-mode.sh"
st = gs.read_text(encoding="utf-8").replace("\r\n", "\n")

old_m = """tunnel_proxy_leg_state() {
    local tunnel_pid="${1:-}"
    local socks_candidate args fwd_needle
    [ -n "$tunnel_pid" ] || { echo unknown; return 0; }
    socks_candidate="$(socks_proxy_port)"
    args="$(ps -p "$tunnel_pid" -o args= 2>/dev/null || true)"
    [ -n "$args" ] || { echo unknown; return 0; }
    fwd_needle="-L 127.0.0.1:${socks_candidate}:127.0.0.1:${XRAY_SERVER_SOCKS_PORT}"
    case "$args" in
        *"$fwd_needle"*)
            if local_port_listening "$socks_candidate"; then
                echo ok
            else
                echo listen_down
            fi
            return 0
            ;;
    esac
    case "$args" in *"-D 127.0.0.1:${socks_candidate}"*) echo legacy_D; return 0 ;; esac
    echo missing
}

tunnel_needs_proxy_reseed() {
    local tunnel_pid="${1:-}"
    [ -n "$tunnel_pid" ] || return 1
    remote_xray_socks_open || return 1
    local state
    state="$(tunnel_proxy_leg_state "$tunnel_pid")"
    case "$state" in
        ok) return 1 ;;
    esac
    # unknown / listen_down / legacy_D / missing → reseed (fail closed while xray is up)
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL reseed_needed reason=$state pid=$tunnel_pid socks=$(socks_proxy_port)" 'WARN'
    fi
    return 0
}"""

new_m = """tunnel_proxy_leg_state() {
    local tunnel_pid="${1:-}"
    local socks_candidate args fwd_needle
    [ -n "$tunnel_pid" ] || { echo unknown; return 0; }
    socks_candidate="$(socks_proxy_port)"
    args="$(ps -p "$tunnel_pid" -o args= 2>/dev/null || true)"
    [ -n "$args" ] || { echo unknown; return 0; }
    fwd_needle="-L 127.0.0.1:${socks_candidate}:127.0.0.1:${XRAY_SERVER_SOCKS_PORT}"
    case "$args" in *"$fwd_needle"*) echo ok; return 0 ;; esac
    case "$args" in *"-D 127.0.0.1:${socks_candidate}"*) echo legacy_D; return 0 ;; esac
    echo missing
}

tunnel_needs_proxy_reseed() {
    local tunnel_pid="${1:-}"
    [ -n "$tunnel_pid" ] || return 1
    remote_xray_socks_open || return 1
    local state
    state="$(tunnel_proxy_leg_state "$tunnel_pid")"
    case "$state" in
        ok|unknown) return 1 ;;
    esac
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL reseed_needed reason=$state pid=$tunnel_pid socks=$(socks_proxy_port)" 'WARN'
    fi
    return 0
}"""

st = replace_once(st, old_m, new_m, "SH state/reseed")
print("SH: state/reseed .38")

st2 = re.sub(
    r"(if declare -F connect_log >/dev/null 2>&1; then\n"
    r"        connect_log \"ENSURE_TUNNEL ok=0 reason=wait_timeout pid=\$bg_pid\" 'WARN'\n"
    r"    fi\n)"
    r"    SOCKS_PROXY_PORT=\"\"\n",
    r"\1",
    st,
    count=1,
)
if st2 != st:
    st = st2
    print("SH: removed wait_timeout SOCKS clear")
else:
    print("SH: wait_timeout SOCKS clear already absent")

gs.write_text(st, encoding="utf-8", newline="\n")

# ===== editor-launch.sh =====
em = ROOT / "scripts/client/editor-launch.sh"
mt = em.read_text(encoding="utf-8").replace("\r\n", "\n")

mt2, n = re.subn(
    r"\nrunning_cursor_proxy_socks_port\(\) \{.*?\n\}\n\n(?=set_cursor_proxy_settings\(\))",
    "\n",
    mt,
    count=1,
    flags=re.S,
)
if n != 1:
    raise SystemExit(f"EM remove running_cursor n={n}")
mt = mt2
print("EM: removed running_cursor_proxy_socks_port")

old_em_proxy = """        # Write proxy settings but NEVER soft-stop for proxy changes (preserves N open windows).
        if [ -n "${SOCKS_PROXY_PORT:-}" ]; then
            _socks_for_settings="$SOCKS_PROXY_PORT"
            if _cli_socks="$(running_cursor_proxy_socks_port)"; then
                if [ -n "$_cli_socks" ] && [ "$_cli_socks" != "$SOCKS_PROXY_PORT" ]; then
                    declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_ALIGN: prefer_running_cli socks=${_cli_socks} session=${SOCKS_PROXY_PORT}" 'INFO'
                    _socks_for_settings="$_cli_socks"
                fi
            fi
            if set_cursor_proxy_settings "$_socks_for_settings"; then
                declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_SET: preserved_open_windows socks=${_socks_for_settings} (no soft-stop)" 'INFO'
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
        fi"""

new_em_proxy = """        _cursor_proxy_needs_relaunch=0
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
        fi"""

mt = replace_once(mt, old_em_proxy, new_em_proxy, "EM proxy/auth")
print("EM: restored .38 proxy+auth soft-stop")
em.write_text(mt, encoding="utf-8", newline="\n")

# ===== versions =====
for rel in ["scripts/client/windows/connect-version.txt", "scripts/client/mac/connect-version.txt"]:
    (ROOT / rel).write_text(TARGET + "\n", encoding="utf-8", newline="\n")

cp = ROOT / "scripts/client/windows/connect.ps1"
tt = cp.read_text(encoding="utf-8")
tt2, n = re.subn(r"ConnectVersion = '20260721\.\d+'", f"ConnectVersion = '{TARGET}'", tt, count=1)
if n != 1:
    raise SystemExit("connect.ps1 version fail")
cp.write_text(tt2, encoding="utf-8", newline="\n")

cs = ROOT / "scripts/client/mac/connect.sh"
tt = cs.read_text(encoding="utf-8")
tt2, n = re.subn(r"CONNECT_VERSION='20260721\.\d+'", f"CONNECT_VERSION='{TARGET}'", tt, count=1)
if n != 1:
    raise SystemExit("connect.sh version fail")
cs.write_text(tt2, encoding="utf-8", newline="\n")
print("versions ->", TARGET)

# ===== sync Claude-Connect from repo (NOT from server bundle) =====
pairs = [
    ("scripts/client/windows/connect.ps1", "connect.ps1"),
    ("scripts/client/windows/connect-version.txt", "connect-version.txt"),
    ("scripts/client/git-mode.ps1", "git-mode.ps1"),
    ("scripts/client/editor-launch.ps1", "editor-launch.ps1"),
    ("scripts/client/git-mode.sh", "mac/git-mode.sh"),
    ("scripts/client/editor-launch.sh", "mac/editor-launch.sh"),
    ("scripts/client/mac/connect.sh", "mac/connect.sh"),
    ("scripts/client/mac/connect-version.txt", "mac/connect-version.txt"),
]
for src, dst in pairs:
    s = ROOT / src
    d = CC / dst
    d.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(s, d)
    print(f"CC sync {dst}")

print("DONE — no deploy performed")
