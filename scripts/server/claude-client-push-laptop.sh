#!/usr/bin/env bash
# claude-client-push-laptop - push /usr/local/share/claude-client to the laptop via reverse tunnel.
# ANY old connect folder recovers without a working local connect-update.ps1.
# Best-effort: never fails the caller.
#
# Windows flash fix (2026-07-27): fleet cron used to run every ~90s with several
# visible cmd.exe / powershell.exe console windows on the laptop. Now:
#   - one hidden EncodedCommand probe (WindowStyle Hidden)
#   - idle stamp 15 min when already up-to-date (no Connect.bat rewrite / dated heal)
#   - heavy heal only when a push is actually needed (or FORCE=1)

set -u

BUNDLE="${CLAUDE_CLIENT_BUNDLE:-/usr/local/share/claude-client}"
CONNECT_CONF="${HOME}/.claude-connect.conf"
KEY="${HOME}/.ssh/claude_laptop"
KNOWN_HOSTS="${HOME}/.ssh/known_hosts_claude_mount"
STAMP_DIR="${HOME}/.cache"
STAMP="${STAMP_DIR}/claude-client-push.stamp"
# When already current: do not SSH to the laptop more often than this.
IDLE_STAMP_SECS="${CLAUDE_CLIENT_PUSH_IDLE_SECS:-900}"

log() { printf '%s CLIENT_PUSH: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >&2; }

LAPTOP_USER=""
TUNNEL_PORT=""
LAPTOP_OS="windows"
if [ -f "$CONNECT_CONF" ]; then
    while IFS='=' read -r k v; do
        v="${v#\"}"; v="${v%\"}"
        v="$(printf '%s' "$v" | tr -d '\r')"
        case "$k" in
            LAPTOP_USER) LAPTOP_USER="$v" ;;
            TUNNEL_PORT) TUNNEL_PORT="$v" ;;
            LAPTOP_OS|laptop_os) LAPTOP_OS="$v" ;;
        esac
    done < "$CONNECT_CONF"
fi

[ -n "${LAPTOP_USER:-}" ] || exit 0
[ -n "${TUNNEL_PORT:-}" ] || exit 0
[ -f "$BUNDLE/connect-version.txt" ] || exit 0
[ -f "$KEY" ] || exit 0

mkdir -p "$STAMP_DIR" 2>/dev/null || true
if [ "${FORCE:-0}" != "1" ] && [ -f "$STAMP" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$IDLE_STAMP_SECS" ]; then
        exit 0
    fi
fi

if ! timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/${TUNNEL_PORT}" 2>/dev/null; then
    exit 0
fi

REMOTE_VER="$(tr -d '\r\n' < "$BUNDLE/connect-version.txt" 2>/dev/null || true)"
[ -n "$REMOTE_VER" ] || exit 0

ssh_l() {
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=no -o ControlPath=none \
        -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" "$@"
}

# Hidden PowerShell on Windows (UTF-16LE EncodedCommand). Avoids cmd.exe flashes.
ssh_l_ps_hidden() {
    local ps_cmd="$1"
    local b64=""
    if ! command -v iconv >/dev/null 2>&1; then
        return 1
    fi
    b64=$(printf '%s' "$ps_cmd" | iconv -f UTF-8 -t UTF-16LE 2>/dev/null | base64 -w 0 2>/dev/null) || true
    [ -n "$b64" ] || return 1
    ssh_l "powershell -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ${b64}"
}

scp_to() {
    # $1 = remote dir using forward slashes
    local dest_ssh="$1"
    shift
    scp -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=no -o ControlPath=none \
        -i "$KEY" -P "$TUNNEL_PORT" "$@" "${LAPTOP_USER}@127.0.0.1:${dest_ssh}/" >/dev/null 2>&1
}

OS_LC="$(printf '%s' "$LAPTOP_OS" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
DESKTOP=""
local_ver=""
has_boot=""
dated_list=""

case "$OS_LC" in
    mac|darwin|osx)
        DESKTOP="$(ssh_l 'printf %s "$HOME/Desktop"' 2>/dev/null | tr -d '\r' || true)"
        ;;
    *)
        # One hidden round-trip: desktop + version + bootstrap presence.
        probe_ps='$ErrorActionPreference="SilentlyContinue"; $ProgressPreference="SilentlyContinue"; $desk=[Environment]::GetFolderPath("Desktop"); $canon=Join-Path $desk "Claude-Connect"; $ver=""; $boot="NO"; $vf=Join-Path $canon "connect-version.txt"; if (Test-Path -LiteralPath $vf) { $ver = (Get-Content -LiteralPath $vf -TotalCount 1 | ForEach-Object { $_.Trim() }) }; if (Test-Path -LiteralPath (Join-Path $canon "connect-bootstrap.ps1")) { $boot="YES" }; Write-Output ("DESKTOP=" + $desk); Write-Output ("VER=" + $ver); Write-Output ("BOOT=" + $boot)'
        probe_out="$(ssh_l_ps_hidden "$probe_ps" 2>/dev/null | tr -d '\r' || true)"
        while IFS= read -r line; do
            case "$line" in
                DESKTOP=*) DESKTOP="${line#DESKTOP=}" ;;
                VER=*) local_ver="${line#VER=}" ;;
                BOOT=*) has_boot="${line#BOOT=}" ;;
            esac
        done <<< "$probe_out"
        if [ -z "$DESKTOP" ]; then
            DESKTOP="$(ssh_l_ps_hidden 'Write-Output ([Environment]::GetFolderPath("Desktop"))' 2>/dev/null | tr -d '\r' | tail -1 || true)"
        fi
        ;;
esac
[ -n "$DESKTOP" ] || { log "no desktop path"; exit 0; }

# Prefer forward slashes for OpenSSH on Windows
DESKTOP_SSH="$(printf '%s' "$DESKTOP" | tr '\\' '/')"
CANON_SSH="${DESKTOP_SSH}/Claude-Connect"

need_push=0
if [ "${FORCE:-0}" = "1" ]; then
    need_push=1
elif [ "$OS_LC" = "mac" ] || [ "$OS_LC" = "darwin" ] || [ "$OS_LC" = "osx" ]; then
    local_ver="$(ssh_l "cat \"$CANON_SSH/connect-version.txt\" 2>/dev/null" 2>/dev/null | tr -d '\r\n' | head -1 || true)"
    has_boot="$(ssh_l "test -f \"$CANON_SSH/connect-bootstrap.ps1\" && echo YES" 2>/dev/null | tr -d '\r\n' || true)"
    if [ "$local_ver" != "$REMOTE_VER" ] || [ "$has_boot" != "YES" ]; then
        need_push=1
    fi
else
    if [ "$local_ver" != "$REMOTE_VER" ] || [ "$has_boot" != "YES" ]; then
        need_push=1
    fi
fi

FILES=()
for f in \
    connect.bat connect-boot.ps1 connect-bootstrap.ps1 connect-heal.ps1 \
    connect.ps1 connect-update.ps1 connect-env-repair.ps1 cursor-proxy-sidecar.ps1 \
    connect-ui.ps1 connect-diagnostic.ps1 editor-launch.ps1 git-mode.ps1 \
    cursor-auth-laptop.ps1 connect-version.txt connect-rider.bat \
    windows-mcp-laptop.ps1
do
    [ -f "$BUNDLE/$f" ] && FILES+=("$BUNDLE/$f")
done
[ "${#FILES[@]}" -gt 0 ] || exit 0

push_dir() {
    local dest_ssh="$1"
    case "$OS_LC" in
        mac|darwin|osx)
            ssh_l "mkdir -p \"$dest_ssh\"" >/dev/null 2>&1 || true
            ;;
        *)
            ssh_l_ps_hidden "New-Item -ItemType Directory -Force -Path '$dest_ssh' | Out-Null" >/dev/null 2>&1 || true
            ;;
    esac
    scp_to "$dest_ssh" "${FILES[@]}"
}

if [ "$need_push" = "1" ]; then
    if push_dir "$CANON_SSH"; then
        log "canon ok ver=$REMOTE_VER user=$(id -un) port=$TUNNEL_PORT"
    else
        log "canon push failed user=$(id -un)"
        date +%s > "$STAMP" 2>/dev/null || true
        exit 0
    fi

    # Heal dated zombie publish folders (old shortcuts) — only when we already pushed.
    case "$OS_LC" in
        mac|darwin|osx) ;;
        *)
            dated_ps='$ErrorActionPreference="SilentlyContinue"; $p=Join-Path $env:USERPROFILE "Desktop\claude-publish"; if (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Directory | Where-Object { $_.Name -match "^claude-code-client-\d{8}$" } | ForEach-Object { (Join-Path $_.FullName "windows") -replace "\\","/" } }'
            dated_list="$(ssh_l_ps_hidden "$dated_ps" 2>/dev/null | tr -d '\r' || true)"
            if [ -n "$dated_list" ]; then
                while IFS= read -r d; do
                    [ -n "$d" ] || continue
                    push_dir "$d" && log "healed dated $d" || true
                done <<< "$dated_list"
            fi
            # Desktop Connect.bat launcher -> Claude-Connect (once per real push)
            shortcut_ps='$ErrorActionPreference="SilentlyContinue"; $bat=Join-Path ([Environment]::GetFolderPath("Desktop")) "Connect.bat"; $body="@echo off`r`nstart \"\" \"%USERPROFILE%\\Desktop\\Claude-Connect\\connect.bat\"`r`n"; [IO.File]::WriteAllText($bat,$body)'
            ssh_l_ps_hidden "$shortcut_ps" >/dev/null 2>&1 || true
            ;;
    esac

    date +%s > "$STAMP" 2>/dev/null || true
    exit 0
fi

# Already current: stamp and exit. Do NOT rewrite Connect.bat or scan dated folders
# (those were the multi-window flashes every ~90s).
date +%s > "$STAMP" 2>/dev/null || true
exit 0
