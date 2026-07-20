#!/bin/bash
# connect-update.sh - check server client bundle; download if newer (Mac/Linux)
# Exit: 0 = continue (up-to-date / unreachable), 1 = update ERROR, 2 = updated (re-exec)

set -uo pipefail
if [ -z "${CLAUDE_CONNECT_RUN_ID:-}" ]; then
    CLAUDE_CONNECT_RUN_ID="$(python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$")"
    export CLAUDE_CONNECT_RUN_ID
fi

REMOTE_BUNDLE="${CLAUDE_CLIENT_BUNDLE:-/usr/local/share/claude-client}"
REMOTE_BUNDLE="${REMOTE_BUNDLE%/}"
SSH_EXTRA_OPTS=(-o IdentitiesOnly=yes -o IdentityAgent=none)

_ensure_run_id() {
    if [ -n "${CLAUDE_CONNECT_RUN_ID:-}" ]; then
        export CLAUDE_CONNECT_RUN_ID
        return 0
    fi
    if command -v uuidgen >/dev/null 2>&1; then
        CLAUDE_CONNECT_RUN_ID="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' | cut -c1-12)"
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        CLAUDE_CONNECT_RUN_ID="$(tr -d '-' < /proc/sys/kernel/random/uuid | tr '[:upper:]' '[:lower:]' | cut -c1-12)"
    else
        CLAUDE_CONNECT_RUN_ID="$(printf '%s%04x' "$(date +%s)" "$$")"
    fi
    export CLAUDE_CONNECT_RUN_ID
}

_ensure_run_id

UPDATE_QUIET=0
[ "${CLAUDE_CONNECT_UPDATE_QUIET:-0}" = "1" ] && UPDATE_QUIET=1

_update_msg() {
    [ "$UPDATE_QUIET" -eq 1 ] && return 0
    # shellcheck disable=SC2059
    printf "$@"
}

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
    NEW_ROOT="$ROOT_DIR/.client-update-new"
    BAK_ROOT="$ROOT_DIR/.client-update-bak"
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
    local server_ip='192.168.210.240' remote_user=''
    if [ -n "${CLAUDE_UPDATE_SSH_TARGET:-}" ]; then
        printf '%s\n' "$CLAUDE_UPDATE_SSH_TARGET"
        return
    fi
    cfg="$HOME/.config/claude-connect/connect.conf"
    if [ -f "$cfg" ]; then
        remote_user="$(grep -E '^REMOTE_USER=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
        local sip
        sip="$(grep -E '^SERVER_IP=' "$cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
        [ -n "$sip" ] && server_ip="$sip"
    fi
    local ps1="$ROOT_DIR/windows/connect.ps1" shf="$MAC_DIR/connect.sh"
    [ -f "$ps1" ] || ps1="$ROOT_DIR/connect.ps1"
    if [ -f "$ps1" ]; then
        local parsed
        parsed="$(grep -E '^\$ServerIP\s*=' "$ps1" 2>/dev/null | head -1 | sed -n 's/.*"\([^"]*\)".*/\1/p')"
        [ -n "$parsed" ] && server_ip="$parsed"
        if [ -z "$remote_user" ]; then
            parsed="$(grep -E '^\$RemoteUser\s*=' "$ps1" 2>/dev/null | head -1 | sed -n "s/.*'\([^']*\)'.*/\1/p")"
            [ -n "$parsed" ] && remote_user="$parsed"
        fi
    fi
    if [ -f "$shf" ]; then
        local parsed
        parsed="$(grep -E '^SERVER_IP=' "$shf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\r')"
        [ -n "$parsed" ] && server_ip="$parsed"
    fi
    # Always user@IP from package - never Host alias claude-server (often Smart).
    if [ -z "$remote_user" ]; then
        case "$server_ip" in
            192.168.250.70) remote_user='sepidz' ;;
            *) remote_user='smart' ;;
        esac
    fi
    printf '%s@%s\n' "$remote_user" "$server_ip"
}

# Kill hung ssh/scp after $1 seconds (macOS has no GNU timeout by default).
_run_timed() {
    local secs="$1"; shift
    local pid watcher ec
    "$@" &
    pid=$!
    (
        sleep "$secs"
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
    ) &
    watcher=$!
    wait "$pid"
    ec=$?
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    return "$ec"
}

_ssh_cat() {
    local target="$1" path="$2"
    _run_timed 20 ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o ControlMaster=no \
        "${SSH_EXTRA_OPTS[@]}" \
        -o StrictHostKeyChecking=accept-new \
        "$target" "cat '$path'" 2>/dev/null
}

_download_bundle() {
    local target="$1" remote_root="$2" local_root="$3"
    rm -rf "$local_root"
    mkdir -p "$local_root"
    _run_timed 180 scp -r -o BatchMode=yes -o ConnectTimeout=20 -o ConnectionAttempts=1 -o ControlMaster=no \
        "${SSH_EXTRA_OPTS[@]}" \
        -o StrictHostKeyChecking=accept-new -q \
        "${target}:${remote_root}/." "$local_root/" 2>/dev/null
}


_update_log_path() {
    local day dir
    day="$(date +%Y%m%d)"
    dir="$HOME/.config/claude-connect/logs"
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s\n' "$dir/connect-${day}.log"
}

_update_file_log() {
    local msg="$1" level="${2:-INFO}"
    local sid="${CLAUDE_CONNECT_RUN_ID:--}"
    local ts
    # Harden: ERROR lines always carry FAIL UPDATE_ for greppable day log.
    if [ "$level" = "ERROR" ]; then
        case "$msg" in
            FAIL\ UPDATE_*) ;;
            *) msg="FAIL UPDATE_: $msg" ;;
        esac
    fi
    if command -v python3 >/dev/null 2>&1; then
        ts="$(python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S.000')"
    else
        ts="$(date '+%Y-%m-%d %H:%M:%S.000')"
    fi
    printf '[%s] [%s] [%s] UPDATE: %s\n' "$ts" "$level" "$sid" "$msg" >> "$(_update_log_path)" 2>/dev/null || true
}

_verify_checksums() {
    local root="$1" sumfile="$1/checksums.txt" line want rel got
    if [ ! -f "$sumfile" ]; then
        _update_file_log "checksums_missing skip_verify" WARN
        return 0
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$'\r'/}"
        [ -n "$line" ] || continue
        case "$line" in \#*) continue ;; esac
        want="$(printf '%s\n' "$line" | awk '{print tolower($1)}')"
        rel="$(printf '%s\n' "$line" | awk '{print substr($0, index($0,$2))}' | sed 's/^\*//; s/^\.\///')"
        [ -n "$want" ] && [ -n "$rel" ] || continue
        [ "$rel" = "checksums.txt" ] && continue
        if [ ! -f "$root/$rel" ]; then
            _update_file_log "checksum_fail missing=$rel" ERROR
            return 1
        fi
        if command -v shasum >/dev/null 2>&1; then
            got="$(shasum -a 256 "$root/$rel" | awk '{print tolower($1)}')"
        elif command -v sha256sum >/dev/null 2>&1; then
            got="$(sha256sum "$root/$rel" | awk '{print tolower($1)}')"
        else
            _update_file_log "checksum_skip no_hasher" WARN
            return 0
        fi
        if [ "$got" != "$want" ]; then
            _update_file_log "checksum_fail mismatch=$rel" ERROR
            return 1
        fi
    done < "$sumfile"
    _update_file_log "checksum_ok"
    return 0
}

_swap_dir() {
    local live="$1" newdir="$2" bak="$3"
    mkdir -p "$(dirname "$bak")"
    if [ -e "$live" ]; then
        rm -rf "$bak"
        if ! mv "$live" "$bak"; then
            return 1
        fi
    fi
    if ! mv "$newdir" "$live"; then
        # rollback
        if [ -e "$bak" ]; then
            rm -rf "$live" 2>/dev/null || true
            mv "$bak" "$live" 2>/dev/null || true
        fi
        return 1
    fi
    return 0
}

main() {
    _resolve_layout

    command -v ssh >/dev/null 2>&1 || { _update_file_log "ssh_missing" ERROR; exit 1; }
    command -v scp >/dev/null 2>&1 || { _update_file_log "scp_missing" ERROR; exit 1; }
    [ -f "$VER_FILE" ] || exit 0

    local local_ver remote_ver target manifest rel src dst failed=0
    local_ver="$(tr -d '\r\n' < "$VER_FILE")"
    _update_file_log "bat_launch local_ver=$local_ver"
    target="$(_get_server_target)"
    _update_msg '  Update source: %s\n' "$target"
    remote_ver="$(_ssh_cat "$target" "$REMOTE_BUNDLE/connect-version.txt" | tr -d '\r\n')"
    if [ -z "$remote_ver" ]; then
        # Fallback: service account (sepidz/smart) when REMOTE_USER key cannot pull bundle.
        ip="${target##*@}"
        case "$ip" in
            192.168.250.70) svc=sepidz ;;
            *) svc=smart ;;
        esac
        fb="${svc}@${ip}"
        if [ "$fb" != "$target" ]; then
            _update_msg '  Update retry via %s\n' "$fb"
            remote_ver="$(_ssh_cat "$fb" "$REMOTE_BUNDLE/connect-version.txt" | tr -d '\r\n')"
            [ -n "$remote_ver" ] && target="$fb"
        fi
    fi
    if [ -z "$remote_ver" ]; then _update_file_log "unreachable target=$target" WARN; exit 0; fi
    _remote_version_newer "$remote_ver" "$local_ver" || exit 0

    _update_msg '  Client update available: v%s -> v%s\n' "$local_ver" "$remote_ver"

    manifest="$(_ssh_cat "$target" "$REMOTE_BUNDLE/manifest.txt")"
    if [ -z "$manifest" ]; then
        _update_file_log "manifest_empty_or_unreachable" ERROR
        exit 1
    fi

    rm -rf "$STAGING_DIR" "$NEW_ROOT" "$BAK_ROOT"
    _update_msg '  downloading client bundle...\n'
    if ! _download_bundle "$target" "$REMOTE_BUNDLE" "$STAGING_DIR"; then
        _update_msg '  [!] Update download failed - using local copy\n'
        _update_file_log "download_failed" ERROR
        rm -rf "$STAGING_DIR"
        exit 1
    fi

    if ! _verify_checksums "$STAGING_DIR"; then
        _update_msg '  [!] Update checksum failed - using local copy\n'
        rm -rf "$STAGING_DIR"
        exit 1
    fi

    failed=0
    while IFS= read -r rel || [ -n "$rel" ]; do
        rel="${rel//$'\r'/}"
        [ -n "$rel" ] || continue
        case "$rel" in
            server/*) continue ;;
        esac
        if [ ! -f "$STAGING_DIR/$rel" ]; then
            failed=1
            break
        fi
    done <<< "$manifest"

    if [ "$failed" -ne 0 ]; then
        _update_msg '  [!] Update incomplete - using local copy\n'
        _update_file_log "incomplete_files" ERROR
        rm -rf "$STAGING_DIR"
        exit 1
    fi

    WIN_DIR="$ROOT_DIR/windows"
    [ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"
    # Flat layout: never nest BAK under WIN_DIR (subdirectory mv bug).
    if [ "$WIN_DIR" = "$ROOT_DIR" ]; then
      _ext="${TMPDIR:-/tmp}/claude-client-update-$$"
      NEW_ROOT="$_ext/new"
      BAK_ROOT="$_ext/bak"
      mkdir -p "$NEW_ROOT/windows" "$NEW_ROOT/mac" "$BAK_ROOT" 2>/dev/null || true
      _day="$HOME/.config/claude-connect/logs/connect-$(date +%Y%m%d).log"
      mkdir -p "$(dirname "$_day")" 2>/dev/null || true
      printf '[%s] [INFO] [%s] UPDATE: flat_layout staging_ext=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${CLAUDE_CONNECT_RUN_ID:--}" "$_ext" >> "$_day" 2>/dev/null || true
    fi
    MAC_OUT="$ROOT_DIR/mac"
    [ -d "$MAC_OUT" ] || MAC_OUT="$MAC_DIR"

    mkdir -p "$NEW_ROOT/windows"
    [ -d "$MAC_OUT" ] && mkdir -p "$NEW_ROOT/mac"

    # Seed from live, then overlay staging (never mutate live in-place).
    if [ -d "$WIN_DIR" ]; then
        cp -a "$WIN_DIR"/. "$NEW_ROOT/windows/" 2>/dev/null || {
            _update_file_log "seed_windows_fail" ERROR
            rm -rf "$STAGING_DIR" "$NEW_ROOT"
            exit 1
        }
    fi
    if [ -d "$MAC_OUT" ] && [ -d "$NEW_ROOT/mac" ]; then
        cp -a "$MAC_OUT"/. "$NEW_ROOT/mac/" 2>/dev/null || {
            _update_file_log "seed_mac_fail" ERROR
            rm -rf "$STAGING_DIR" "$NEW_ROOT"
            exit 1
        }
    fi

    failed=0
    while IFS= read -r rel || [ -n "$rel" ]; do
        rel="${rel//$'\r'/}"
        [ -n "$rel" ] || continue
        case "$rel" in
            server/*) continue ;;
        esac
        src="$STAGING_DIR/$rel"
        case "$rel" in
            mac/*)
                dst="$NEW_ROOT/mac/${rel#mac/}"
                ;;
            *)
                dst="$NEW_ROOT/windows/$rel"
                ;;
        esac
        mkdir -p "$(dirname "$dst")"
        if ! cp -f "$src" "$dst"; then
            failed=1
            _update_file_log "copy_fail rel=$rel" ERROR
            break
        fi
    done <<< "$manifest"

    if [ "$failed" -ne 0 ]; then
        _update_msg '  [!] Update copy failed - using local copy\n'
        rm -rf "$STAGING_DIR" "$NEW_ROOT" "$BAK_ROOT"
        exit 1
    fi

    if [ -f "$NEW_ROOT/windows/connect-version.txt" ] && [ -d "$NEW_ROOT/mac" ]; then
        cp -f "$NEW_ROOT/windows/connect-version.txt" "$NEW_ROOT/mac/connect-version.txt" 2>/dev/null || true
    fi

    if ! _swap_dir "$WIN_DIR" "$NEW_ROOT/windows" "$BAK_ROOT/windows"; then
        _update_msg '  [!] Update apply failed - rolled back\n'
        _update_file_log "apply_rollback windows" ERROR
        rm -rf "$STAGING_DIR" "$NEW_ROOT" "$BAK_ROOT"
        exit 1
    fi
    if [ -d "$NEW_ROOT/mac" ]; then
        mkdir -p "$(dirname "$MAC_OUT")"
        if ! _swap_dir "$MAC_OUT" "$NEW_ROOT/mac" "$BAK_ROOT/mac"; then
            _update_msg '  [!] Update apply failed - rolled back\n'
            _update_file_log "apply_rollback mac" ERROR
            # restore windows
            if [ -d "$BAK_ROOT/windows" ]; then
                rm -rf "$WIN_DIR"
                mv "$BAK_ROOT/windows" "$WIN_DIR" 2>/dev/null || true
            fi
            rm -rf "$STAGING_DIR" "$NEW_ROOT" "$BAK_ROOT"
            exit 1
        fi
    fi

    rm -rf "$STAGING_DIR" "$NEW_ROOT" "$BAK_ROOT"
    _update_msg '  Updated to v%s\n' "$remote_ver"
    _update_file_log "applied_ok need_relaunch exit=2"
    exit 2
}

main "$@"
