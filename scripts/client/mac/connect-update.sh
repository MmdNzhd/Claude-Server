#!/bin/bash
# connect-update.sh - check server client bundle; download if newer (Mac/Linux)
# Exit: 0 = continue, 2 = updated (re-exec connect.sh)

set -uo pipefail

REMOTE_BUNDLE="${CLAUDE_CLIENT_BUNDLE:-/usr/local/share/claude-client}"
REMOTE_BUNDLE="${REMOTE_BUNDLE%/}"

_connect_version_parts() {
    local v="$1" date build
    if [[ "$v" =~ ^([0-9]{8})\.([0-9]+)$ ]]; then
        date="${BASH_REMATCH[1]}"
        build="${BASH_REMATCH[2]}"
        printf '%s %s\n' "$date" "$build"
        return 0
    fi
    return 1
}

_remote_version_newer() {
    local remote="$1" local_v="$2"
    [ -n "$remote" ] && [ -n "$local_v" ] || return 1
    [ "$remote" = "$local_v" ] && return 1
    local rd rb ld lb
    if read -r rd rb < <(_connect_version_parts "$remote") &&
       read -r ld lb < <(_connect_version_parts "$local_v"); then
        if [ "$rd" -ne "$ld" ]; then
            [ "$rd" -gt "$ld" ]
            return
        fi
        [ "$rb" -gt "$lb" ]
        return
    fi
    [[ "$remote" > "$local_v" ]]
}

_resolve_layout() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ "$(basename "$SCRIPT_DIR")" = "mac" ]; then
        ROOT_DIR="$(dirname "$SCRIPT_DIR")"
        MAC_DIR="$SCRIPT_DIR"
    else
        ROOT_DIR="$SCRIPT_DIR"
        MAC_DIR="$SCRIPT_DIR/mac"
    fi
    STAGING_DIR="$ROOT_DIR/.client-update-staging"
    VER_FILE=""
    for _vf in \
        "$ROOT_DIR/connect-version.txt" \
        "$ROOT_DIR/windows/connect-version.txt" \
        "$MAC_DIR/connect-version.txt"; do
        if [ -f "$_vf" ]; then
            VER_FILE="$_vf"
            break
        fi
    done
}

_get_server_target() {
    local server_ip='192.168.210.240' alias='claude-server' remote_user
    remote_user="$(whoami)"
    local ps1="$ROOT_DIR/connect.ps1"
    if [ -f "$ps1" ]; then
        local parsed
        parsed="$(grep -E '^\$ServerIP\s*=' "$ps1" 2>/dev/null | head -1 | sed -n 's/.*"\([^"]*\)".*/\1/p')"
        [ -n "$parsed" ] && server_ip="$parsed"
    fi
    local cfg="$HOME/.config/claude-connect/connect.conf"
    if [ -f "$cfg" ]; then
        local ru
        ru="$(grep -E '^REMOTE_USER=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
        [ -n "$ru" ] && remote_user="$ru"
    fi
    if [ -f "$HOME/.ssh/config" ] && grep -qE '^Host[[:space:]]+claude-server[[:space:]]*$' "$HOME/.ssh/config" 2>/dev/null; then
        printf '%s\n' "$alias"
        return
    fi
    printf '%s@%s\n' "$remote_user" "$server_ip"
}

_ssh_cat() {
    local target="$1" path="$2"
    ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
        "$target" "cat '$path'" 2>/dev/null
}

_scp_file() {
    local target="$1" remote="$2" local_path="$3"
    local parent
    parent="$(dirname "$local_path")"
    [ -d "$parent" ] || mkdir -p "$parent"
    scp -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -q \
        "${target}:${remote}" "$local_path" 2>/dev/null
}

_download_bundle() {
    local target="$1" remote_root="$2" local_root="$3"
    rm -rf "$local_root"
    mkdir -p "$local_root"
    scp -r -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -q \
        "${target}:${remote_root}/." "$local_root/" 2>/dev/null
}

main() {
    _resolve_layout

    command -v ssh >/dev/null 2>&1 || exit 0
    command -v scp >/dev/null 2>&1 || exit 0
    [ -f "$VER_FILE" ] || exit 0

    local local_ver remote_ver target manifest rel src dst failed=0
    local_ver="$(tr -d '\r\n' < "$VER_FILE")"
    target="$(_get_server_target)"
    remote_ver="$(_ssh_cat "$target" "$REMOTE_BUNDLE/connect-version.txt" | tr -d '\r\n')"
    [ -n "$remote_ver" ] || exit 0
    _remote_version_newer "$remote_ver" "$local_ver" || exit 0

    printf '  Client update available: v%s -> v%s\n' "$local_ver" "$remote_ver"

    manifest="$(_ssh_cat "$target" "$REMOTE_BUNDLE/manifest.txt")"
    [ -n "$manifest" ] || exit 0

    rm -rf "$STAGING_DIR"
    printf '  downloading client bundle...\n'
    if ! _download_bundle "$target" "$REMOTE_BUNDLE" "$STAGING_DIR"; then
        printf '  [!] Update download failed - using local copy\n'
        rm -rf "$STAGING_DIR"
        exit 0
    fi

    failed=0
    while IFS= read -r rel || [ -n "$rel" ]; do
        rel="${rel//$'\r'/}"
        [ -n "$rel" ] || continue
        if [ ! -f "$STAGING_DIR/$rel" ]; then
            failed=1
            break
        fi
    done <<< "$manifest"

    if [ "$failed" -ne 0 ]; then
        printf '  [!] Update incomplete - using local copy\n'
        rm -rf "$STAGING_DIR"
        exit 0
    fi

    while IFS= read -r rel || [ -n "$rel" ]; do
        rel="${rel//$'\r'/}"
        [ -n "$rel" ] || continue
        src="$STAGING_DIR/$rel"
        dst="$ROOT_DIR/$rel"
        mkdir -p "$(dirname "$dst")"
        cp -f "$src" "$dst"
    done <<< "$manifest"

    rm -rf "$STAGING_DIR"
    printf '  Updated to v%s\n' "$remote_ver"
    exit 2
}

main "$@"
