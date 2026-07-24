#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="$HOME/.claude-mounts.d"
CONNECT_CONF="$HOME/.claude-connect.conf"
KEY="$HOME/.ssh/claude_laptop"
KNOWN_HOSTS="$HOME/.ssh/known_hosts_claude_mount"

# ---------------------------------------------------------------------------
# Globals (populated by _load_global)
# ---------------------------------------------------------------------------
LAPTOP_USER=""
TUNNEL_PORT=""
GIT_MODE="off"    # off = no rename (default), hide = fast, server = SSHFS git
LAPTOP_OS="windows"  # windows | mac - how to run laptop-side git hide/restore
ACTIVE_MOUNT=""   # set by connect.bat - only this project may auto-mount
_MOUNT_SAVED_GIT_MODE="off"  # GIT_MODE snapshot for _do_mount RETURN trap (must not be local)
_GIT_HIDE_LAST_FAILED=0       # set by _emit_git_hide_warn; read by _do_mount (must not be local)
_TUNNEL_OK_THIS_UP=""         # set by cmd_up once it verifies the tunnel; read by hide helpers below
                              # to skip a duplicate probe within the same `up` invocation (must not be local)

_load_global() {
    GIT_MODE="off"
    LAPTOP_OS="windows"
    if [ -f "$CONNECT_CONF" ]; then
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            # Strip CRLF (Windows-written conf) - parity with claude-watchdog
            v="$(printf '%s' "$v" | tr -d '\r')"
            case "$k" in
                LAPTOP_USER)  LAPTOP_USER="$v" ;;
                TUNNEL_PORT)  TUNNEL_PORT="$v" ;;
                GIT_MODE|git_mode) GIT_MODE="$v" ;;
                LAPTOP_OS|laptop_os) LAPTOP_OS="$v" ;;
                ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
            esac
        done < "$CONNECT_CONF"
    fi
    if [ -z "$TUNNEL_PORT" ]; then
        # Deprecated fallback removed: `20000 + uid` overlapped by up to 6 of 10 ports
        # between adjacent-UID users (see Get-TunnelPortUserBase in git-mode.ps1 /
        # tunnel_port_user_base in git-mode.sh for the canonical formula and history).
        # This branch should almost never run - the client normally always publishes a
        # real TUNNEL_PORT via Push-ServerConnectConf - so treat it as a rare safety net,
        # not a silent guess: slot is unknowable here (claude-mount.sh only has `id -u`),
        # so default to slot 0 and warn loudly rather than guessing wrong quietly.
        local _uid _offset
        _uid=$(id -u)
        _offset=$((_uid - 1000))
        [ "$_offset" -lt 0 ] && _offset=0
        TUNNEL_PORT=$((20000 + _offset * 10))
        echo "warn: TUNNEL_PORT missing from $CONNECT_CONF - falling back to slot-0 guess $TUNNEL_PORT (20000+(uid-1000)*10+0); this is only a safety net and usually means the client failed to publish TUNNEL_PORT - reconnect connect.bat/connect.sh" >&2
    fi
    case "${GIT_MODE,,}" in
        server|on|yes|1|slow) GIT_MODE="server" ;;
        hide|fast) GIT_MODE="hide" ;;
        off|no|none|0|disabled|"") GIT_MODE="off" ;;
        *) GIT_MODE="off" ;;
    esac
    case "${LAPTOP_OS,,}" in
        mac|darwin|osx) LAPTOP_OS="mac" ;;
        *) LAPTOP_OS="windows" ;;
    esac
}

# ---------------------------------------------------------------------------
# Git hiding - hides .git on Windows by renaming to .git.server-session
# so that git tools on the server never stat() files over SSHFS.
# All operations are best-effort: failures are silently ignored so they
# never block mount/unmount.
#
# Self-healing contract:
#   _hide_git   : idempotent - skips if .git.server-session already exists
#   _restore_git: idempotent - skips if .git already exists
#   cmd_recover : restores all hidden gits for currently-unmounted projects
#
# Edge cases handled:
#   - empty rpath, missing LAPTOP_USER/TUNNEL_PORT -> skip silently
#   - SSH timeout/auth failure -> skip silently (git stays as-is)
#   - single quotes in path -> escaped for PowerShell single-quoted string
#   - .git is a FILE (gitdir pointer for worktrees) -> not renamed (-PathType Container)
#   - both .git and .git.server-session exist -> skip (manual state, don't touch)
#   - .git.server-session exists already -> skip (idempotent)
# ---------------------------------------------------------------------------
# _laptop_ssh - SSH to laptop via reverse tunnel (no mux - avoids stale ControlSocket errors).
_laptop_ssh() {
    if [ -z "$LAPTOP_USER" ] || [ -z "$TUNNEL_PORT" ]; then
        return 0
    fi
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=no -o ControlPath=none \
        -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" \
        "$@"
}

# _win_ps_encode - run PowerShell via -EncodedCommand (avoids quote nesting over SSH).
_win_ps_encode() {
    local ps_cmd="$1"
    local b64=""
    if command -v iconv >/dev/null 2>&1; then
        b64=$(printf '%s' "$ps_cmd" | iconv -f UTF-8 -t UTF-16LE 2>/dev/null | base64 -w 0 2>/dev/null)
    fi
    [ -n "$b64" ] || return 1
    _laptop_ssh "powershell -NoProfile -EncodedCommand ${b64}" 2>/dev/null || true
}

# _win_ps - runs a PowerShell snippet on a Windows laptop via reverse tunnel.
_win_ps() {
    _win_ps_encode "$1"
}

# _win_ps_out - like _win_ps but returns stdout (for git-hide status checks).
_win_ps_out() {
    local ps_cmd="$1"
    if [ -z "$LAPTOP_USER" ] || [ -z "$TUNNEL_PORT" ]; then
        return 0
    fi
    _win_ps_encode "$ps_cmd"
}

# _mac_sh - runs a bash snippet on a Mac laptop via reverse tunnel.
_mac_sh() {
    local sh_cmd="$1"
    if [ -z "$LAPTOP_USER" ] || [ -z "$TUNNEL_PORT" ]; then
        return 0
    fi
    _laptop_ssh "$sh_cmd" 2>/dev/null || true
}

_hide_git() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    _git_tunnel_ready || { echo "warn: laptop tunnel down - cannot hide .git" >&2; return 0; }
    _hide_git_and_create_stubs "$rpath"
}

_restore_git() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ] || return 0
    # Prefer healthy tunnel; if probe fails but TCP still open (watchdog DOWN race),
    # still attempt restore. SSH ConnectTimeout=5 bounds hang; skip if TCP closed.
    if ! _git_tunnel_ready; then
        _tunnel_tcp_open || return 0
    fi
    _restore_git_body "$rpath"
}

_rpath_for_this_laptop() {
    local rpath="$1"
    rpath="${rpath//\\//}"
    rpath="$(printf '%s' "$rpath" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "${LAPTOP_OS,,}" in
        mac|darwin)
            case "$rpath" in
                [A-Za-z]:*) return 1 ;;
            esac
            ;;
        *)
            case "$rpath" in
                /Users/*) return 1 ;;
            esac
            ;;
    esac
    return 0
}

_restore_git_body() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    local safe="${rpath//\'/\'\'}"
    if [ "$LAPTOP_OS" = "mac" ]; then
        # Never clobber a real .git dir when both exist; only replace a worktree pointer file.
        _mac_sh "p='${safe}'; if [ -e \"\$p/.git.server-session\" ]; then if [ -d \"\$p/.git\" ]; then :; elif [ -f \"\$p/.git\" ]; then rm -f \"\$p/.git\" && mv \"\$p/.git.server-session\" \"\$p/.git\"; elif [ ! -e \"\$p/.git\" ]; then mv \"\$p/.git.server-session\" \"\$p/.git\"; fi; fi"
    else
        _win_ps "\$p='${safe}'; if (Test-Path \$p/.git.server-session) { if ((Test-Path \$p/.git -PathType Container) -and (Test-Path \$p/.git/HEAD)) { } elseif (Test-Path \$p/.git -PathType Leaf) { Remove-Item \$p/.git -Force -ErrorAction SilentlyContinue; Rename-Item \$p/.git.server-session .git -Force -ErrorAction SilentlyContinue } elseif (-not (Test-Path \$p/.git)) { Rename-Item \$p/.git.server-session .git -Force -ErrorAction SilentlyContinue } }"
    fi
}


_emit_git_hide_warn() {
    local ps_out="$1"
    ps_out="${ps_out//$'\r'/}"
    local hide_status
    hide_status=$(printf '%s\n' "$ps_out" | grep -o 'GIT_HIDE:.*' | tail -1 || true)
    _GIT_HIDE_LAST_FAILED=0
    case "$hide_status" in
        GIT_HIDE:fail:*)
            _GIT_HIDE_LAST_FAILED=1
            echo "warn: git hide failed - ${hide_status#GIT_HIDE:fail:} (close Cursor/git on laptop, then reconnect; common causes: Windows Search Indexer, antivirus/Defender scan, or Cursor/git itself locking .git)" >&2
            ;;
        GIT_HIDE:skip|GIT_HIDE:already|GIT_HIDE:hidden|GIT_HIDE:restored|GIT_HIDE:visible|"")
            ;;
        *)
            ;;
    esac
}

# Require laptop tunnel before git hide/restore (best-effort).
_git_tunnel_ready() {
    [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ] && _tunnel_up
}

# WS4: single decision point for "is the tunnel ok for a hide/restore/stub operation".
# If cmd_up already verified the tunnel for this whole `up` invocation (_TUNNEL_OK_THIS_UP=1),
# reuse that instead of re-probing - but this function is ONLY ever used to gate whether the
# hide/restore/stub body below still RUNS; it never causes that body to be skipped by itself.
_tunnel_ok_for_hide() {
    [ "${_TUNNEL_OK_THIS_UP:-}" = "1" ] && return 0
    if [ "${CLAUDE_TRUSTED_TUNNEL:-}" = "1" ]; then
        _tunnel_tcp_open && _tunnel_banner_matches_laptop
        return $?
    fi
    _tunnel_up
}

# PERF: emit PERF_<LABEL>_MS=<ms> to stderr when CLAUDE_CONNECT_PERF_LOG=1 (client parses this
# out of the `claude-mount up` stdout/stderr in Invoke-MountProject).
_perf_ms_now() {
    date +%s%3N 2>/dev/null || echo 0
}

_perf_emit() {
    local label="$1" start="$2" end
    [ "${CLAUDE_CONNECT_PERF_LOG:-}" = "1" ] || return 0
    end="$(_perf_ms_now)"
    echo "PERF_${label}_MS=$(( end - start ))" >&2
}

_mac_hide_git_and_create_stubs() {
    local rpath="$1"
    local safe="${rpath//\'/\'\'}"
    local out=""
    if [ "$GIT_MODE" = "server" ]; then
        out=$(_mac_sh "\
p='${safe}'; \
has=0; [ -e \"\$p/.git\" ] || [ -e \"\$p/.git.server-session\" ] && has=1; \
if [ -e \"\$p/.git.server-session\" ] && [ -d \"\$p/.git\" ]; then echo GIT_HIDE:skip; \
elif [ -e \"\$p/.git.server-session\" ] && [ -f \"\$p/.git\" ]; then \
  rm -f \"\$p/.git\" 2>/dev/null; mv \"\$p/.git.server-session\" \"\$p/.git\" 2>/dev/null && echo GIT_HIDE:restored || echo GIT_HIDE:fail:mv_denied; \
elif [ -e \"\$p/.git.server-session\" ] && [ ! -e \"\$p/.git\" ]; then \
  n=0; ok=0; while [ \$n -lt 2 ]; do n=\$((n+1)); chmod -R u+w \"\$p/.git.server-session\" 2>/dev/null || true; mv \"\$p/.git.server-session\" \"\$p/.git\" 2>/dev/null && { echo GIT_HIDE:restored; ok=1; break; }; \
  if [ \$n -lt 2 ]; then pkill -x git 2>/dev/null || true; sleep 0.5; fi; done; \
  [ \$ok -eq 0 ] && echo GIT_HIDE:fail:mv_denied; \
elif [ -e \"\$p/.git\" ]; then echo GIT_HIDE:visible; fi; \
if [ \"\$has\" = 1 ]; then mkdir -p \"\$p/.claude/rules\" \"\$p/.claude/commands\"; [ ! -s \"\$p/.mcp.json\" ] && printf '{}' > \"\$p/.mcp.json\"; fi\
")
    else
        out=$(_mac_sh "\
p='${safe}'; \
if [ ! -e \"\$p/.git\" ] && [ ! -e \"\$p/.git.server-session\" ]; then echo GIT_HIDE:skip; \
elif [ -e \"\$p/.git.server-session\" ] && [ ! -e \"\$p/.git\" ]; then echo GIT_HIDE:already; \
elif [ -f \"\$p/.git\" ]; then echo GIT_HIDE:skip; \
elif [ -d \"\$p/.git\" ] && [ ! -e \"\$p/.git.server-session\" ]; then \
  n=0; ok=0; while [ \$n -lt 2 ]; do n=\$((n+1)); chmod -R u+w \"\$p/.git\" 2>/dev/null || true; mv \"\$p/.git\" \"\$p/.git.server-session\" 2>/dev/null && { echo GIT_HIDE:hidden; ok=1; break; }; \
  if [ \$n -lt 2 ]; then pkill -x git 2>/dev/null || true; sleep 0.5; fi; done; \
  [ \$ok -eq 0 ] && echo GIT_HIDE:fail:mv_denied; \
else echo GIT_HIDE:skip; fi; \
has=0; [ -e \"\$p/.git\" ] || [ -e \"\$p/.git.server-session\" ] && has=1; \
if [ \"\$has\" = 1 ]; then mkdir -p \"\$p/.claude/rules\" \"\$p/.claude/commands\"; [ ! -s \"\$p/.mcp.json\" ] && printf '{}' > \"\$p/.mcp.json\"; fi\
")
    fi
    _emit_git_hide_warn "$out"
}

_win_hide_git_and_create_stubs() {
    local rpath="$1"
    local safe="${rpath//\'/\'\'}"
    local ps_out=""
    # Single-line PS (no trailing \\) - backslashes break powershell -Command over SSH.
    local hide_try='$n=0; $ok=$false; $err=""; if (-not (Test-Path $p/.git) -and -not (Test-Path $p/.git.server-session)) { Write-Output "GIT_HIDE:skip"; exit }; if (Test-Path $p/.git -PathType Leaf) { Write-Output "GIT_HIDE:skip" } elseif ((Test-Path $p/.git -PathType Container) -and (Test-Path $p/.git.server-session)) { Write-Output "GIT_HIDE:skip" } elseif ((Test-Path $p/.git -PathType Container) -and -not (Test-Path $p/.git.server-session)) { while ($n -lt 2) { $n++; try { cmd /c "attrib -R `"$p\.git`" /S /D" 2>$null | Out-Null; Rename-Item $p/.git .git.server-session -Force -ErrorAction Stop; Write-Output "GIT_HIDE:hidden"; $ok=$true; break } catch { $err=$_.Exception.Message; if ($n -lt 2) { Get-Process git -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 } } }; if (-not $ok) { Write-Output ("GIT_HIDE:fail:" + $err) } } elseif (Test-Path $p/.git.server-session) { Write-Output "GIT_HIDE:already" } else { Write-Output "GIT_HIDE:skip" }'
    local restore_try='if (Test-Path $p/.git.server-session) { if ((Test-Path $p/.git -PathType Container) -and (Test-Path $p/.git/HEAD)) { Write-Output "GIT_HIDE:skip" } elseif ((Test-Path $p/.git) -and -not (Test-Path $p/.git -PathType Leaf)) { Write-Output "GIT_HIDE:skip" } else { $n=0; $ok=$false; $err=""; while ($n -lt 2) { $n++; try { if (Test-Path $p/.git -PathType Leaf) { Remove-Item $p/.git -Force -ErrorAction SilentlyContinue }; if (Test-Path $p/.git) { Write-Output "GIT_HIDE:skip"; $ok=$true; break }; cmd /c "attrib -R `"$p\.git.server-session`" /S /D" 2>$null | Out-Null; Rename-Item $p/.git.server-session .git -Force -ErrorAction Stop; Write-Output "GIT_HIDE:restored"; $ok=$true; break } catch { $err=$_.Exception.Message; if ($n -lt 2) { Get-Process git -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 } } }; if (-not $ok) { Write-Output ("GIT_HIDE:fail:" + $err) } } } elseif (Test-Path $p/.git) { Write-Output "GIT_HIDE:visible" } else { Write-Output "GIT_HIDE:skip" }'
    local stub_ps='; if ($hasGit) { New-Item -ItemType Directory -Force -Path $p/.claude/rules,$p/.claude/commands | Out-Null; if (-not (Test-Path $p/.mcp.json) -or (Get-Item $p/.mcp.json).Length -eq 0) { Set-Content -Path $p/.mcp.json -Value "{}" -Encoding utf8 } }'
    local ps_prefix ps_cmd
    ps_prefix="\$p='${safe}'; \$hasGit=(Test-Path \$p/.git) -or (Test-Path \$p/.git.server-session); "
    if [ "$GIT_MODE" = "server" ]; then
        ps_cmd="${ps_prefix}${restore_try}${stub_ps}"
        ps_out=$(_win_ps_out "$ps_cmd")
    else
        ps_cmd="${ps_prefix}${hide_try}${stub_ps}"
        ps_out=$(_win_ps_out "$ps_cmd")
    fi
    _emit_git_hide_warn "$ps_out"
}

# Hide .git AND create .claude/ stubs in a single SSH connection.
# Stubs prevent Claude Code from doing one SFTP round-trip per missing path (~3s each).
# Called on every mount (new and already-mounted) so stubs always exist.
#

_create_claude_stubs_only() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    if [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ] && ! _tunnel_ok_for_hide; then
        return 0
    fi
    local safe="${rpath//\'/\'\'}"
    if [ "$LAPTOP_OS" = "mac" ]; then
        _mac_sh "\
p='${safe}'; \
h=0; [ -e \"\$p/.git\" ] || [ -e \"\$p/.git.server-session\" ] && h=1; \
if [ \"\$h\" = 1 ]; then mkdir -p \"\$p/.claude/rules\" \"\$p/.claude/commands\"; [ -s \"\$p/.mcp.json\" ] || printf '{}' > \"\$p/.mcp.json\"; fi\
"
    else
        _win_ps_out "\$p='${safe}'; \$hasGit=(Test-Path \$p/.git) -or (Test-Path \$p/.git.server-session); if (\$hasGit) { New-Item -ItemType Directory -Force -Path \$p/.claude/rules,\$p/.claude/commands | Out-Null; if (-not (Test-Path \$p/.mcp.json) -or (Get-Item \$p/.mcp.json).Length -eq 0) { Set-Content -Path \$p/.mcp.json -Value '{}' -Encoding utf8 } }" >/dev/null || true
    fi
}

# GIT_MODE=hide: rename .git -> .git.server-session (fast git on server)
# GIT_MODE=server: keep .git visible on mount (slow SSHFS git; user preference)
_hide_git_and_create_stubs() {
    local rpath="$1" _perf_t0
    [ -z "$rpath" ] && return 0
    if [ "$GIT_MODE" = "off" ]; then
        if [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ] && ! _tunnel_ok_for_hide; then
            echo "warn: laptop tunnel down - cannot restore .git (reconnect connect.bat)" >&2
            return 0
        fi
        _perf_t0="$(_perf_ms_now)"
        _restore_git_body "$rpath"
        _create_claude_stubs_only "$rpath"
        _perf_emit HIDE "$_perf_t0"
        return 0
    fi
    if [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ] && ! _tunnel_ok_for_hide; then
        echo "warn: laptop tunnel down - git mode not applied (reconnect connect.bat)" >&2
        return 0
    fi
    _perf_t0="$(_perf_ms_now)"
    if [ "$LAPTOP_OS" = "mac" ]; then
        _mac_hide_git_and_create_stubs "$rpath"
    else
        _win_hide_git_and_create_stubs "$rpath"
    fi
    _perf_emit HIDE "$_perf_t0"
}

# GIT_MODE=off|hide: disable Cursor SCM git over SSHFS (avoids "Failed to execute git").
# GIT_MODE=server: re-enable / clear stuck git.enabled=false from a prior hide session.
# Only remote User settings (NOT workspace .vscode) so laptop-local git stays enabled.
_apply_git_scm_policy() {
    local lpath="$1"
    [ -n "$lpath" ] && [ -d "$lpath" ] || return 0
    # hide/off: disable Cursor SCM over SSHFS. server: re-enable / clear stuck false.
    python3 - "${HOME:-}" "$GIT_MODE" <<'SCM_PY' 2>/dev/null || true
import json, os, sys

home = sys.argv[1] if len(sys.argv) > 1 else ""
mode = (sys.argv[2] if len(sys.argv) > 2 else "off").lower()
if not home:
    raise SystemExit(0)
disable = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}
# Keys we may have stuck false after hide->server; restore usable defaults.
enable_keys = (
    "git.enabled",
    "git.autoRepositoryDetection",
    "git.detectSubmodules",
    "git.repositoryScanMaxDepth",
)

def merge_settings(path: str) -> None:
    parent = os.path.dirname(path)
    # only if this remote editor profile already exists
    top = os.path.dirname(os.path.dirname(parent))  # .../data
    if not os.path.isdir(top):
        return
    os.makedirs(parent, exist_ok=True)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, json.JSONDecodeError):
        data = {}
    changed = False
    if mode == "server":
        # Clear stuck disables from a prior hide session
        for k in enable_keys:
            if k == "git.enabled" and data.get(k) is False:
                data[k] = True
                changed = True
            elif k == "git.autoRepositoryDetection" and data.get(k) is False:
                data[k] = True
                changed = True
            elif k == "git.detectSubmodules" and data.get(k) is False:
                data[k] = True
                changed = True
            elif k == "git.repositoryScanMaxDepth" and data.get(k) == 0:
                data.pop(k, None)
                changed = True
    else:
        for k, v in disable.items():
            if data.get(k) != v:
                data[k] = v
                changed = True
    if changed or not os.path.isfile(path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")

for rel in (
    ".cursor-server/data/User/settings.json",
    ".vscode-server/data/User/settings.json",
):
    merge_settings(os.path.join(home, rel))
SCM_PY
}

_warm_sshfs_cache() {
    local lpath="$1"
    _apply_git_scm_policy "$lpath"
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        /usr/local/bin/laptop-exec-setup --project "$lpath" 2>/dev/null || true
    fi
    (
        timeout 5 ls "$lpath/.claude/"          >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/commands/" >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.cursor/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.vscode/"          >/dev/null 2>&1 || true
    ) &
}

# ---------------------------------------------------------------------------
# Tunnel / mount checks
# ---------------------------------------------------------------------------
_tunnel_tcp_open() {
    timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null
}

_tunnel_banner() {
    timeout 3 nc 127.0.0.1 "$TUNNEL_PORT" 2>/dev/null | head -1 | tr -d '\r\n'
}

_tunnel_banner_matches_laptop() {
    local banner="${1:-}"
    [ -n "$banner" ] || banner="$(_tunnel_banner)"
    [ -n "$banner" ] || return 1
    echo "$banner" | grep -q '^SSH-2.0-' || return 1
    case "${LAPTOP_OS,,}" in
        mac|darwin)
            # macOS Remote Login is plain OpenSSH. Reject Windows + common Linux/package banners.
            echo "$banner" | grep -qi 'OpenSSH' || return 1
            echo "$banner" | grep -qiE 'OpenSSH_for_Windows|Ubuntu|Debian|el[0-9]+|Fedora|fc[0-9]|Alpine|Raspbian|CentOS|Rocky|Alma|SUSE|FreeBSD|AMI|\bLinux\b' && return 1
            # Packaged Linux often has "OpenSSH_XpY <distro...>" (space after pN)
            echo "$banner" | grep -qiE 'OpenSSH_[0-9.]+p[0-9]+[[:space:]]' && return 1
            ;;
        *)
            echo "$banner" | grep -qi 'OpenSSH_for_Windows' || return 1
            ;;
    esac
    return 0
}

_tunnel_auth_ok() {
    [ -n "$LAPTOP_USER" ] && [ -f "$KEY" ] || return 1
    local rcmd=true
    case "${LAPTOP_OS,,}" in
        mac|darwin|osx) rcmd=true ;;
        *) rcmd='cmd /c exit 0' ;;
    esac
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=no -o ControlPath=none \
        -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" $rcmd 2>/dev/null
}

_tunnel_up() {
    _tunnel_tcp_open || return 1
    _tunnel_banner_matches_laptop || return 1
    _tunnel_auth_ok
}

_tunnel_diagnose() {
    local banner="" rc=0
    _load_global
    echo "TUNNEL_PORT=${TUNNEL_PORT:-}"
    echo "LAPTOP_USER=${LAPTOP_USER:-}"
    echo "LAPTOP_OS=${LAPTOP_OS:-}"
    if _tunnel_tcp_open; then
        echo "tcp=open"
    else
        echo "tcp=closed"
        rc=1
    fi
    banner="$(_tunnel_banner 2>/dev/null || true)"
    if [ -n "$banner" ]; then
        echo "banner=$banner"
    else
        echo "banner="
        rc=1
    fi
    if _tunnel_banner_matches_laptop "$banner"; then
        echo "banner_match=yes"
    else
        echo "banner_match=no"
        rc=1
    fi
    if _tunnel_auth_ok; then
        echo "auth=ok"
    else
        echo "auth=fail"
        rc=1
    fi
    return "$rc"
}

_in_proc_mounts() {
    local mp="${1%/}"
    [ -n "$mp" ] || return 1
    # Instant; never hangs on frozen SSHFS (unlike mountpoint -q).
    grep -F " $mp " /proc/mounts >/dev/null 2>&1
}

_is_mounted() {
    local lpath="$1"
    _in_proc_mounts "$lpath" && \
        timeout -k 1 2 ls "$lpath" >/dev/null 2>&1
}

# Try every available unmount method, from clean to lazy. Always returns 0.
_do_unmount() {
    local lpath="$1"
    fusermount  -u  "$lpath" 2>/dev/null || \
    fusermount3 -u  "$lpath" 2>/dev/null || \
    fusermount  -uz "$lpath" 2>/dev/null || \
    fusermount3 -uz "$lpath" 2>/dev/null || \
    umount -l "$lpath" 2>/dev/null || true
}

# Unmount lpath (including hung sshfs) then restore .git on rpath.
_force_unmount_project() {
    local lpath="$1" rpath="$2"
    if [ -z "$lpath" ]; then
        [ -n "$rpath" ] && _restore_git "$rpath"
        return 0
    fi
    if ! _in_proc_mounts "$lpath"; then
        [ -n "$rpath" ] && _restore_git "$rpath"
        return 0
    fi
    if timeout -k 1 2 ls "$lpath" >/dev/null 2>&1; then
        _do_unmount "$lpath"
    else
        local lpath_esc
        lpath_esc=$(printf '%s' "$lpath" | sed 's/[[\.*^$(){}+?|]/\\&/g')
        pkill -u "$USER" -f "sshfs .*${lpath_esc}" 2>/dev/null || true
        sleep 1
        _do_unmount "$lpath"
    fi
    if _is_mounted "$lpath"; then
        echo "error: unmount failed: $lpath" >&2
        return 1
    fi
    echo "unmounted: $lpath"
    [ -n "$rpath" ] && _restore_git "$rpath"
    return 0
}

_mount_restore_git_mode() {
    GIT_MODE="${_MOUNT_SAVED_GIT_MODE:-off}"
}

# ---------------------------------------------------------------------------
# Core mount
# ---------------------------------------------------------------------------
_do_mount() {
    local conf_file="$1"
    local id="" label="" rpath="" lpath="" mount_git_mode=""

    [ -f "$conf_file" ] || { echo "error: conf not found: $conf_file" >&2; return 1; }

    _MOUNT_SAVED_GIT_MODE="$GIT_MODE"

    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            id|MOUNT_ID)       id="$v" ;;
            label|MOUNT_LABEL) label="$v" ;;
            rpath|REMOTE_PATH) rpath="$v" ;;
            lpath|LOCAL_PATH)  lpath="$v" ;;
            git_mode|GIT_MODE) mount_git_mode="$v" ;;
        esac
    done < "$conf_file"

    if [ -n "$mount_git_mode" ]; then
        case "${mount_git_mode,,}" in
            server|on|yes|1|slow) GIT_MODE="server" ;;
            hide|fast) GIT_MODE="hide" ;;
            off|no|none|0|disabled) GIT_MODE="off" ;;
        esac
    fi

    lpath="${lpath//\\//}"
    rpath="${rpath//\\//}"

    if _is_mounted "$lpath"; then
        if [ "$GIT_MODE" = "off" ]; then
            echo "already mounted: $lpath"
            _hide_git_and_create_stubs "$rpath"
            _warm_sshfs_cache "$lpath"
            _mount_restore_git_mode
            return 0
        fi
        # Server mode needs a fresh mount so SSHFS sees .git after restore on laptop.
        if [ "$GIT_MODE" = "server" ]; then
            _do_unmount "$lpath"
            sleep 1
        else
            echo "already mounted: $lpath"
            # Fast path: hide already reflected on the mount - skip reverse-SSH hide (~2-3s).
            if [ "${CLAUDE_TRUSTED_TUNNEL:-}" = "1" ] && \
               { [ ! -e "$lpath/.git" ] || [ -e "$lpath/.git.server-session" ]; } && \
               [ "$_GIT_HIDE_LAST_FAILED" != "1" ]; then
                _warm_sshfs_cache "$lpath"
                _mount_restore_git_mode
                return 0
            fi
            # Hide not yet applied (or untrusted) - (re)apply hide/stubs via reverse SSH.
            _hide_git_and_create_stubs "$rpath"
            if [ "${CLAUDE_TRUSTED_TUNNEL:-}" = "1" ] && \
               { [ ! -e "$lpath/.git" ] || [ -e "$lpath/.git.server-session" ]; } && \
               [ "$_GIT_HIDE_LAST_FAILED" != "1" ]; then
                _warm_sshfs_cache "$lpath"
                _mount_restore_git_mode
                return 0
            fi
            # SSHFS cache may keep stale .git after laptop rename - remount if .git still visible.
            # Skip the remount when the hide itself genuinely failed (e.g. access denied) -
            # a fresh mount won't clear a laptop-side lock, so retrying just doubles the wait
            # and repeats the same warning for no benefit.
            if [ "$GIT_MODE" = "hide" ] && [ -e "$lpath/.git" ] && [ ! -e "$lpath/.git.server-session" ] && [ "$_GIT_HIDE_LAST_FAILED" != "1" ]; then
                _do_unmount "$lpath"
                sleep 1
            else
                _warm_sshfs_cache "$lpath"
                _mount_restore_git_mode
                return 0
            fi
        fi
    fi

    # Clean stale mountpoint (use lazy unmount -uz in case the mount is frozen)
    if _in_proc_mounts "$lpath"; then
        _do_unmount "$lpath"
        sleep 1
    fi

    # mkdir -p can fail with I/O error if lpath is under a stale parent mount
    if ! mkdir -p "$lpath" 2>/dev/null; then
        _do_unmount "$lpath"
        sleep 1
        if ! timeout 5 mkdir -p "$lpath" 2>/dev/null; then
            echo "error: cannot create mountpoint $lpath" >&2
            _mount_restore_git_mode
            return 1
        fi
    fi

    # Hide .git and create Claude stubs in one SSH call - from here on, any failure must restore .git
    _hide_git_and_create_stubs "$rpath"

    local sshfs_opts="reconnect,ServerAliveInterval=15,ServerAliveCountMax=4,idmap=user,allow_other,StrictHostKeyChecking=accept-new,UserKnownHostsFile=${KNOWN_HOSTS},ConnectTimeout=20,dir_cache=yes,dcache_timeout=60,attr_timeout=30,entry_timeout=30,max_conns=4"
    local id_opt=""
    [ -f "$KEY" ] && id_opt=",IdentityFile=$KEY"

    local sshfs_out sshfs_exit=0 _perf_sshfs_t0
    _perf_sshfs_t0="$(_perf_ms_now)"
    sshfs_out=$(timeout 30 sshfs -o "${sshfs_opts}${id_opt}" \
        "${LAPTOP_USER}@127.0.0.1:${rpath}" "${lpath}" \
        -p "${TUNNEL_PORT}" 2>&1) || sshfs_exit=$?
    _perf_emit SSHFS "$_perf_sshfs_t0"

    if [ "$sshfs_exit" -ne 0 ]; then
        # sshfs failed - restore .git only if we hid it
        if [ "$GIT_MODE" = "hide" ]; then _restore_git "$rpath"; fi
        local reason="$sshfs_out"
        # Check specific errors FIRST so a timed-out sshfs that printed a real
        # error before being killed (exit 124) still shows the actionable message.
        if echo "$reason" | grep -qi "host key verification failed\|remote host identification has changed"; then
            reason="laptop host key changed (laptop reinstalled?) - run: ssh-keygen -R [127.0.0.1]:${TUNNEL_PORT} -f ${KNOWN_HOSTS}"
        elif echo "$reason" | grep -qi "permission denied\|publickey"; then
            reason="key auth failed - re-run connect.bat to reinstall the key"
        elif echo "$reason" | grep -qi "connection reset\|reset by peer"; then
            reason="connection reset - laptop SSH rejected the key (re-run connect.bat to reinstall)"
        elif echo "$reason" | grep -qi "no such file\|cannot find\|not found"; then
            reason="path not found on laptop: $rpath"
        elif echo "$reason" | grep -qi "connection refused"; then
            reason="laptop SSH not running (connection refused)"
        elif [ "$sshfs_exit" -eq 124 ] || [ -z "$reason" ]; then
            reason="laptop SSH not responding (timeout)"
        fi
        echo "error: mount failed - $reason" >&2
        _mount_restore_git_mode
        return 1
    fi

    if ! timeout 10 ls -A "$lpath" >/dev/null 2>&1; then
        # mount came up but is not readable - restore .git and clean up
        _restore_git "$rpath"
        echo "error: mount verification failed for $lpath" >&2
        _do_unmount "$lpath"
        _mount_restore_git_mode
        return 1
    fi

    echo "mounted: $lpath"
    _warm_sshfs_cache "$lpath"
    _mount_restore_git_mode
    return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_list() {
    mkdir -p "$CONF_DIR"
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local id="" label="" rpath="" lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id|MOUNT_ID)       id="$v" ;;
                label|MOUNT_LABEL) label="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
            esac
        done < "$f"
        echo "${id}|${label}|${rpath}|${lpath}"
    done
}

cmd_tunnel_status() {
    _tunnel_diagnose
}

cmd_status() {
    mkdir -p "$CONF_DIR"
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local id="" label="" rpath="" lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id|MOUNT_ID)       id="$v" ;;
                label|MOUNT_LABEL) label="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
            esac
        done < "$f"
        local status="OFF"
        _is_mounted "$lpath" 2>/dev/null && status="MOUNTED"
        echo "${id}|${label}|${lpath}|${status}"
    done
}

cmd_add() {
    local id label rpath lpath
    if [ $# -ge 4 ]; then
        id="$1"; label="$2"; rpath="$3"; lpath="$4"
    else
        printf "ID: "; read -r id
        printf "Label: "; read -r label
        printf "Remote path: "; read -r rpath
        printf "Local path: "; read -r lpath
    fi

    mkdir -p "$CONF_DIR"
    local conf="$CONF_DIR/${id}.conf"
    printf 'id=%s\nlabel=%s\nrpath=%s\nlpath=%s\n' "$id" "$label" "$rpath" "$lpath" > "$conf"
    echo "added: $id ($label)"
}

cmd_edit() {
    local id="$1"
    local new_label="${2:-}"
    local new_rpath="${3:-}"
    local new_lpath="${4:-}"
    local conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { echo "error: not found: $id" >&2; return 1; }

    local cur_label="" cur_rpath="" cur_lpath=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            label) cur_label="$v" ;;
            rpath) cur_rpath="$v" ;;
            lpath) cur_lpath="$v" ;;
        esac
    done < "$conf"

    # Save old rpath before any modification
    local old_rpath="${cur_rpath//\\//}"

    if [ -n "$new_label" ] || [ -n "$new_rpath" ] || [ -n "$new_lpath" ]; then
        # Non-interactive: use provided args, keep current value if arg is empty
        [ -n "$new_label" ] && cur_label="$new_label"
        [ -n "$new_rpath" ] && cur_rpath="$new_rpath"
        [ -n "$new_lpath" ] && cur_lpath="$new_lpath"
    else
        # Interactive (local terminal)
        printf "Label [%s]: " "$cur_label"; read -r v; [ -n "$v" ] && cur_label="$v"
        printf "Remote path [%s]: " "$cur_rpath"; read -r v; [ -n "$v" ] && cur_rpath="$v"
        printf "Local path [%s]: " "$cur_lpath"; read -r v; [ -n "$v" ] && cur_lpath="$v"
    fi

    # If rpath changed, restore .git at old path before losing the reference
    local cur_rpath_norm="${cur_rpath//\\//}"
    if [ -n "$old_rpath" ] && [ "$cur_rpath_norm" != "$old_rpath" ]; then
        _load_global
        _restore_git "$old_rpath"
    fi

    printf 'id=%s\nlabel=%s\nrpath=%s\nlpath=%s\n' "$id" "$cur_label" "$cur_rpath" "$cur_lpath" > "$conf"
    echo "updated: $id"
}

cmd_rm() {
    local id="$1"
    local conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { echo "error: not found: $id" >&2; return 1; }

    _load_global

    # Read paths before deleting config - once config is gone, rpath is lost forever
    local rpath="" lpath=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            rpath|REMOTE_PATH) rpath="$v" ;;
            lpath|LOCAL_PATH)  lpath="$v" ;;
        esac
    done < "$conf"
    rpath="${rpath//\\//}"
    lpath="${lpath//\\//}"

    # Unmount first so SSHFS isn't left pointing at a removed project
    if [ -n "$lpath" ] && _is_mounted "$lpath" 2>/dev/null; then
        _do_unmount "$lpath"
    fi

    # Restore .git on Windows before losing the rpath reference
    [ -n "$rpath" ] && _restore_git "$rpath"

    rm -f "$conf"
    echo "removed: $id"
}

# Restore .git for all projects whose mount is NOT currently active.
# Called at session start (connect.bat, automount) to recover from crashes.
# Safe to call while other mounts are active - mounted projects are skipped.
cmd_check() {
    _load_global
    local id="$1" conf="" lpath=""
    [ -n "$id" ] || { echo "need_mount"; return 1; }
    conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { echo "need_mount"; return 1; }
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            lpath|LOCAL_PATH) lpath="$v" ;;
        esac
    done < "$conf"
    lpath="${lpath//\\//}"
    if [ -n "$lpath" ] && _is_mounted "$lpath"; then
        echo "ok"
        return 0
    fi
    echo "need_mount"
    return 1
}

cmd_recover_if_needed() {
    _load_global
    local id="${1:-}"
    if [ -n "$id" ] && cmd_check "$id" >/dev/null 2>&1; then
        case "${GIT_MODE,,}" in
            server|on|yes|1|slow|hide|fast)
                echo "recover: skip (mount ok)"
                return 0
                ;;
        esac
        echo "recover: mount ok, applying GIT_MODE=off restore"
        local conf="$CONF_DIR/${id}.conf" rpath=""
        [ -f "$conf" ] || { echo "recover: skip (no conf)"; return 0; }
        while IFS='=' read -r k v; do
            v="${v#\"}"; v="${v%\"}"
            case "$k" in rpath|REMOTE_PATH) rpath="$v" ;; esac
        done < "$conf"
        rpath="${rpath//\\//}"
        [ -n "$rpath" ] && _hide_git_and_create_stubs "$rpath"
        echo "recover: off restore done"
        return 0
    fi
    if [ -n "$id" ]; then
        cmd_recover_one "$id"
    else
        cmd_recover
    fi
}

# Restore .git for one project id when its mount is not active.
# Usage: claude-mount recover-one 'projectid'
cmd_recover_one() {
    local id="$1"
    [ -n "$id" ] || { echo "error: need project id" >&2; return 1; }
    _load_global
    local conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { echo "error: not found: $id" >&2; return 1; }
    local rpath="" lpath="" lpath_esc tunnel_ok=0
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            rpath|REMOTE_PATH) rpath="$v" ;;
            lpath|LOCAL_PATH)  lpath="$v" ;;
        esac
    done < "$conf"
    rpath="${rpath//\\//}"
    lpath="${lpath//\\//}"
    _rpath_for_this_laptop "$rpath" || return 0
    [ -n "$lpath" ] && [ -n "$rpath" ] || return 0
    _tunnel_up && tunnel_ok=1
    if ! _in_proc_mounts "$lpath"; then
        [ "$tunnel_ok" -eq 1 ] && _restore_git_body "$rpath"
    elif ! timeout -k 1 2 ls "$lpath" >/dev/null 2>&1; then
        lpath_esc=$(printf '%s' "$lpath" | sed 's/[[\.*^$(){}+?|]/\\&/g')
        pkill -u "$USER" -f "sshfs .*${lpath_esc}" 2>/dev/null || true
        sleep 1
        _do_unmount "$lpath"
        [ "$tunnel_ok" -eq 1 ] && _restore_git_body "$rpath"
    fi
}

cmd_recover() {
    _load_global
    mkdir -p "$CONF_DIR"
    local tunnel_ok=0 f rpath lpath lpath_esc
    _tunnel_up && tunnel_ok=1
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        rpath="" lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                rpath|REMOTE_PATH) rpath="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
            esac
        done < "$f"
        rpath="${rpath//\\//}"
        lpath="${lpath//\\//}"
        _rpath_for_this_laptop "$rpath" || continue
        if [ -n "$lpath" ] && [ -n "$rpath" ]; then
            if ! _in_proc_mounts "$lpath"; then
                [ "$tunnel_ok" -eq 1 ] && _restore_git_body "$rpath"
            elif ! timeout -k 1 2 ls "$lpath" >/dev/null 2>&1; then
                lpath_esc=$(printf '%s' "$lpath" | sed 's/[[\.*^$(){}+?|]/\\&/g')
                pkill -u "$USER" -f "sshfs .*${lpath_esc}" 2>/dev/null || true
                sleep 1
                _do_unmount "$lpath"
                [ "$tunnel_ok" -eq 1 ] && _restore_git_body "$rpath"
            fi
        fi
    done
}

cmd_up() {
    _load_global

    if [ -z "$LAPTOP_USER" ]; then
        echo "error: LAPTOP_USER not set in $CONNECT_CONF" >&2
        return 1
    fi

    # ALWAYS check the raw TCP port first, regardless of any client-side hint below.
    if ! _tunnel_tcp_open; then
        echo "error: reverse tunnel not up on port $TUNNEL_PORT" >&2
        return 1
    fi
    # WS4: the client may already have confirmed the banner via its own probe this session
    # (Test-TunnelUp) and passes both flags together - skip our duplicate SSH banner probe
    # ONLY in that combination; TRUSTED alone is not enough, and this never replaces the
    # _tunnel_tcp_open check above.
    if [ "${CLAUDE_TUNNEL_BANNER_OK:-}" = "1" ] && [ "${CLAUDE_TRUSTED_TUNNEL:-}" = "1" ]; then
        :
    elif ! _tunnel_banner_matches_laptop; then
        echo "error: port $TUNNEL_PORT is another laptop (stale TUNNEL_PORT?) - reconnect connect from this Mac/PC" >&2
        return 1
    fi
    if [ "${CLAUDE_TRUSTED_TUNNEL:-}" != "1" ]; then
        if ! _tunnel_auth_ok; then
            echo "error: laptop SSH rejected key on port $TUNNEL_PORT" >&2
            return 1
        fi
    fi
    # Tunnel is verified for this whole `up` invocation - let hide/stub helpers below skip
    # their own duplicate probe (they still always run the hide/restore/stub body itself).
    _TUNNEL_OK_THIS_UP=1

    local target="${1:-}"

    if [ -n "$target" ]; then
        local conf="$CONF_DIR/${target}.conf"
        [ -f "$conf" ] || { echo "error: not found: $target" >&2; return 1; }
        _do_mount "$conf"
        local mount_ec=$?
        # Any-version heal: push latest client scripts to laptop (never block mount)
        if [ -x /usr/local/bin/claude-client-push-laptop ]; then
            /usr/local/bin/claude-client-push-laptop >/dev/null 2>&1 || true
        fi
        return $mount_ec
    else
        local any_error=0
        for f in "$CONF_DIR"/*.conf; do
            [ -f "$f" ] || continue
            _do_mount "$f" || any_error=1
        done
        if [ -x /usr/local/bin/claude-client-push-laptop ]; then
            /usr/local/bin/claude-client-push-laptop >/dev/null 2>&1 || true
        fi
        return $any_error
    fi
}

# Unmount every project except $1 and restore .git on the laptop.
# Used when connect.bat selects one project so automount does not leave others mounted.
cmd_down_others() {
    _load_global
    local keep="${1:-}"
    mkdir -p "$CONF_DIR"
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local id="" lpath="" rpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id|MOUNT_ID)       id="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
            esac
        done < "$f"
        lpath="${lpath//\\//}"
        rpath="${rpath//\\//}"
        [ -n "$keep" ] && [ "$id" = "$keep" ] && continue
        if [ -n "$lpath" ] && [ -n "$rpath" ]; then
            _force_unmount_project "$lpath" "$rpath" || true
        elif [ -n "$rpath" ]; then
            _restore_git "$rpath"
        fi
    done
}

cmd_down() {
    _load_global

    local target="${1:-}"

    if [ -n "$target" ]; then
        local conf="$CONF_DIR/${target}.conf"
        [ -f "$conf" ] || { echo "error: not found: $target" >&2; return 1; }
        local lpath="" rpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                lpath|LOCAL_PATH)  lpath="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
            esac
        done < "$conf"
        lpath="${lpath//\\//}"
        rpath="${rpath//\\//}"

        if [ -n "$lpath" ]; then
            if _in_proc_mounts "$lpath"; then
                _force_unmount_project "$lpath" "$rpath" || return 1
            else
                echo "not mounted: $lpath"
                [ -n "$rpath" ] && _restore_git "$rpath"
            fi
        elif [ -n "$rpath" ]; then
            _restore_git "$rpath"
        fi
    else
        for f in "$CONF_DIR"/*.conf; do
            [ -f "$f" ] || continue
            local lpath="" rpath=""
            while IFS='=' read -r k v; do
                v="${v#\"}" v="${v%\"}"
                case "$k" in
                    lpath|LOCAL_PATH)  lpath="$v" ;;
                    rpath|REMOTE_PATH) rpath="$v" ;;
                esac
            done < "$f"
            lpath="${lpath//\\//}"
            rpath="${rpath//\\//}"
            if _is_mounted "$lpath" 2>/dev/null; then
                _force_unmount_project "$lpath" "$rpath" || true
            else
                # Not mounted - still restore in case .git was hidden by a crashed session
                _restore_git "$rpath"
            fi
        done
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
cmd="${1:-list}"
shift 2>/dev/null || true

case "$cmd" in
    list)                cmd_list ;;
    status)              cmd_status ;;
    add)                 cmd_add "$@" ;;
    edit)                cmd_edit "$@" ;;
    rm|remove|del)       cmd_rm "$@" ;;
    up|mount)            cmd_up "$@" ;;
    down|umount|unmount) cmd_down "$@" ;;
    down-others)         cmd_down_others "$@" ;;
    recover)             cmd_recover ;;
    recover-one)         cmd_recover_one "$@" ;;
    recover-if-needed)   cmd_recover_if_needed "$@" ;;
    check)               cmd_check "$@" ;;
    tunnel-status)       cmd_tunnel_status ;;
    *)
        echo "Usage: claude-mount {list|status|check|tunnel-status|add|edit|rm|up|down|down-others|recover|recover-one|recover-if-needed} [id]" >&2
        exit 1
        ;;
esac





