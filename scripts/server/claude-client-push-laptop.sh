#!/usr/bin/env bash
# claude-client-push-laptop - push /usr/local/share/claude-client to the laptop via reverse tunnel.
# ANY old connect folder recovers without a working local connect-update.ps1.
# Best-effort: never fails the caller.

set -u

BUNDLE="${CLAUDE_CLIENT_BUNDLE:-/usr/local/share/claude-client}"
CONNECT_CONF="${HOME}/.claude-connect.conf"
KEY="${HOME}/.ssh/claude_laptop"
KNOWN_HOSTS="${HOME}/.ssh/known_hosts_claude_mount"
STAMP_DIR="${HOME}/.cache"
STAMP="${STAMP_DIR}/claude-client-push.stamp"

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
    if [ "$age" -lt 90 ]; then
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

scp_to() {
    # $1 = remote dir using forward slashes
    local dest_ssh="$1"
    shift
    scp -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=no -o ControlPath=none \
        -i "$KEY" -P "$TUNNEL_PORT" "$@" "${LAPTOP_USER}@127.0.0.1:${dest_ssh}/" >/dev/null 2>&1
}

DESKTOP=""
case "$(printf '%s' "$LAPTOP_OS" | tr '[:upper:]' '[:lower:]')" in
    mac|darwin|osx)
        DESKTOP="$(ssh_l 'printf %s "$HOME/Desktop"' 2>/dev/null | tr -d '\r' || true)"
        ;;
    *)
        DESKTOP="$(ssh_l 'powershell -NoProfile -Command Write-Output([Environment]::GetFolderPath(\"Desktop\"))' 2>/dev/null | tr -d '\r' | tail -1 || true)"
        if [ -z "$DESKTOP" ]; then
            DESKTOP="$(ssh_l 'cmd /c echo %USERPROFILE%\\Desktop' 2>/dev/null | tr -d '\r' | tail -1 || true)"
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
else
    local_ver="$(ssh_l "cmd /c if exist \"%USERPROFILE%\\Desktop\\Claude-Connect\\connect-version.txt\" type \"%USERPROFILE%\\Desktop\\Claude-Connect\\connect-version.txt\"" 2>/dev/null | tr -d '\r\n' | head -1 || true)"
    has_boot="$(ssh_l "cmd /c if exist \"%USERPROFILE%\\Desktop\\Claude-Connect\\connect-bootstrap.ps1\" (echo YES)" 2>/dev/null | tr -d '\r\n' || true)"
    if [ "$local_ver" != "$REMOTE_VER" ] || [ "$has_boot" != "YES" ]; then
        need_push=1
    fi
fi

FILES=()
for f in \
    connect.bat connect-boot.ps1 connect-bootstrap.ps1 connect-heal.ps1 \
    connect.ps1 connect-update.ps1 cursor-proxy-sidecar.ps1 \
    connect-ui.ps1 connect-diagnostic.ps1 editor-launch.ps1 git-mode.ps1 \
    cursor-auth-laptop.ps1 connect-version.txt connect-rider.bat
do
    [ -f "$BUNDLE/$f" ] && FILES+=("$BUNDLE/$f")
done
[ "${#FILES[@]}" -gt 0 ] || exit 0

push_dir() {
    local dest_ssh="$1"
    ssh_l "mkdir -p \"$dest_ssh\" 2>/dev/null || powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$dest_ssh' | Out-Null\"" >/dev/null 2>&1 || true
    scp_to "$dest_ssh" "${FILES[@]}"
}

if [ "$need_push" = "1" ]; then
    if push_dir "$CANON_SSH"; then
        log "canon ok ver=$REMOTE_VER user=$(id -un) port=$TUNNEL_PORT"
    else
        log "canon push failed user=$(id -un)"
        exit 0
    fi
fi

# Heal dated zombie publish folders (old shortcuts)
dated_list="$(ssh_l 'powershell -NoProfile -Command "$p=Join-Path $env:USERPROFILE \"Desktop\\claude-publish\"; if(Test-Path -LiteralPath $p){ Get-ChildItem -LiteralPath $p -Directory | Where-Object { $_.Name -match \"^claude-code-client-\\d{8}$\" } | ForEach-Object { (Join-Path $_.FullName \"windows\") -replace \"\\\\\",\"/\" } }"' 2>/dev/null | tr -d '\r' || true)"
if [ -n "$dated_list" ]; then
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        push_dir "$d" && log "healed dated $d" || true
    done <<< "$dated_list"
fi

# Desktop Connect.bat launcher -> Claude-Connect
ssh_l 'powershell -NoProfile -Command "$bat=Join-Path ([Environment]::GetFolderPath(\"Desktop\")) \"Connect.bat\"; $body=\"@echo off`r`nstart \"\" \"%USERPROFILE%\\Desktop\\Claude-Connect\\connect.bat\"`r`n\"; [IO.File]::WriteAllText($bat,$body)"' >/dev/null 2>&1 || true

date +%s > "$STAMP" 2>/dev/null || true
exit 0
