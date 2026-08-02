# editor-launch.sh - shared VS Code/Cursor launch (sourced by connect.sh)

get_editor_pref() {
    local cfg="$1" f="$cfg/editor.conf" saved
    [ -f "$f" ] || { printf 'cursor'; return 0; }
    saved="$(cat "$f" 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')"
    case "$saved" in
        code|vscode) printf 'code' ;;
        ask) printf 'ask' ;;
        cursor) printf 'cursor' ;;
        rider|both) printf 'cursor' ;;
        *) printf 'cursor' ;;
    esac
}

configure_editor_pref() {
    local cfg="$1" cur choice val
    cur="$(get_editor_pref "$cfg")"
    echo ""
    printf '    \033[1;37mIDE preference\033[0m\n\n'
    printf '    \033[0;90mCurrent: %s\033[0m\n\n' "$cur"
    printf '    \033[0;90m1  cursor - always open Cursor\033[0m\n'
    printf '    \033[0;90m2  code   - always open VS Code\033[0m\n'
    printf '    \033[0;90m3  ask    - pick each connect\033[0m\n\n'
    read -rp '    > ' choice
    case "$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')" in
        1|cursor|c) val=cursor ;;
        2|code|vscode|v) val=code ;;
        3|ask|a) val=ask ;;
        *) warn 'Invalid choice.'; return 1 ;;
    esac
    printf '%s' "$val" > "$cfg/editor.conf" 2>/dev/null || true
    printf '    \033[0;32mSaved: %s\033[0m\n\n' "$val"
}

# Resolve absolute CLI path when `cursor`/`code` are not on PATH (common on Mac).
_editor_cli_path() {
    local name="$1" p
    command -v "$name" >/dev/null 2>&1 && { command -v "$name"; return 0; }
    case "$name" in
        cursor)
            for p in \
                "$HOME/.local/bin/cursor" \
                /usr/local/bin/cursor \
                /opt/homebrew/bin/cursor \
                "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
            do
                [ -x "$p" ] && { printf '%s' "$p"; return 0; }
            done
            ;;
        code)
            for p in \
                "$HOME/.local/bin/code" \
                /usr/local/bin/code \
                /opt/homebrew/bin/code \
                "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            do
                [ -x "$p" ] && { printf '%s' "$p"; return 0; }
            done
            ;;
    esac
    return 1
}

resolve_editor_choice() {
    # EDITOR_CMD stays logical (cursor|code) — Mac connect gates auth sync on
    # exact "$EDITOR_CMD" = "cursor". Absolute CLI path goes in EDITOR_BIN only.
    local cfg="$1" pref have_cursor="" have_code="" cursor_bin="" code_bin=""
    EDITOR_BIN=""
    cursor_bin="$(_editor_cli_path cursor)" && have_cursor=1
    code_bin="$(_editor_cli_path code)" && have_code=1
    if [ -z "$have_cursor" ] && [ -z "$have_code" ]; then
        return 1
    fi
    if [ -n "$have_cursor" ] && [ -z "$have_code" ]; then
        EDITOR_CMD=cursor; EDITOR_BIN="${cursor_bin:-}"; EDITOR_NAME=Cursor; return 0
    fi
    if [ -z "$have_cursor" ] && [ -n "$have_code" ]; then
        EDITOR_CMD=code; EDITOR_BIN="${code_bin:-}"; EDITOR_NAME="VS Code"; return 0
    fi
    pref="$(get_editor_pref "$cfg")"
    if [ "$pref" = "ask" ] || [ "$pref" != "cursor" ] && [ "$pref" != "code" ]; then
        echo ""
        printf '    \033[1;37mOpen with\033[0m\n\n'
        printf '    \033[0;90m1  Cursor\033[0m\n'
        printf '    \033[0;90m2  VS Code\033[0m\n\n'
        local ed_choice saved=cursor
        [ "$pref" = "code" ] && saved=code
        printf '    \033[0;90m(Enter = %s)\033[0m\n' "$saved"
        read -r ed_choice
        case "$(printf '%s' "$ed_choice" | tr '[:upper:]' '[:lower:]')" in
            1|cursor|c) EDITOR_CMD=cursor; EDITOR_BIN="${cursor_bin:-}"; EDITOR_NAME=Cursor ;;
            2|code|vscode|v) EDITOR_CMD=code; EDITOR_BIN="${code_bin:-}"; EDITOR_NAME="VS Code" ;;
            "") [ "$saved" = "code" ] && { EDITOR_CMD=code; EDITOR_BIN="${code_bin:-}"; EDITOR_NAME="VS Code"; } \
                                      || { EDITOR_CMD=cursor; EDITOR_BIN="${cursor_bin:-}"; EDITOR_NAME=Cursor; } ;;
            *) EDITOR_CMD=cursor; EDITOR_BIN="${cursor_bin:-}"; EDITOR_NAME=Cursor ;;
        esac
        return 0
    fi
    if [ "$pref" = "code" ]; then
        EDITOR_CMD=code; EDITOR_BIN="${code_bin:-}"; EDITOR_NAME="VS Code"
    else
        EDITOR_CMD=cursor; EDITOR_BIN="${cursor_bin:-}"; EDITOR_NAME=Cursor
    fi
    return 0
}

# Resolve runnable CLI: prefer EDITOR_BIN when it matches the logical cmd.
_editor_run_cmd() {
    local logical="$1"
    if [ -n "${EDITOR_BIN:-}" ] && [ -x "${EDITOR_BIN}" ]; then
        case "$EDITOR_BIN" in
            */"$logical"|*/"$logical".*) printf '%s' "$EDITOR_BIN"; return 0 ;;
        esac
        # basename match (e.g. .../bin/cursor)
        [ "$(basename "$EDITOR_BIN")" = "$logical" ] && { printf '%s' "$EDITOR_BIN"; return 0; }
    fi
    if command -v "$logical" >/dev/null 2>&1; then
        command -v "$logical"
        return 0
    fi
    _editor_cli_path "$logical"
}

get_cursor_remote_profile_site() {
    if [ -n "${CURSOR_PROFILE_SITE:-}" ]; then
        case "$(printf '%s' "$CURSOR_PROFILE_SITE" | tr '[:upper:]' '[:lower:]')" in
            sepidz*) printf '%s' 'Sepidz'; return 0 ;;
            smart*) printf '%s' 'Smart'; return 0 ;;
        esac
    fi
    ip="${SERVER_IP:-${CONNECT_SERVER_IP:-}}"
    case "$ip" in
        192.168.250.70) printf '%s' 'Sepidz'; return 0 ;;
        192.168.210.240) printf '%s' 'Smart'; return 0 ;;
    esac
    case "${ALIAS:-${SSH_ALIAS:-}}" in
        *sepidz*) printf '%s' 'Sepidz'; return 0 ;;
    esac
    printf '%s' 'Smart'
}

_cursor_profile_dir_size_mb() {
    local p="$1"
    if [ ! -d "$p" ]; then
        printf '%s' '0'
        return 0
    fi
    # du -sm: size in MB (GNU/BSD). Fail-open to 0.
    du -sm "$p" 2>/dev/null | awk '{print $1+0}' || printf '%s' '0'
}

_stop_cursor_profile_procs_soft() {
    local line pid cmd
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        pid="${line%% *}"
        cmd="${line#* }"
        case "$cmd" in *ClaudeServerCursorProfile*) ;; *) continue ;; esac
        kill "$pid" 2>/dev/null || true
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    sleep 2
}

ensure_cursor_remote_profile_migrated() {
    # One-time: legacy ClaudeServerCursorProfile -> ClaudeServerCursorProfile-Smart|Sepidz
    # Personal ~/Library/Application Support/Cursor is never touched.
    if [ "${_CURSOR_PROFILE_MIGRATE_CHECKED:-0}" = "1" ]; then
        return 0
    fi
    _CURSOR_PROFILE_MIGRATE_CHECKED=1
    if [ "${CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE:-}" = "1" ]; then
        return 0
    fi
    local site legacy target stamp legacy_mb target_mb bak
    site="$(get_cursor_remote_profile_site)"
    legacy="$HOME/Library/Application Support/ClaudeServerCursorProfile"
    target="$HOME/Library/Application Support/ClaudeServerCursorProfile-${site}"
    stamp="$target/.claude-connect-profile-migrated"
    [ -d "$legacy" ] || return 0
    [ -f "$stamp" ] && return 0

    legacy_mb="$(_cursor_profile_dir_size_mb "$legacy")"
    target_mb="$(_cursor_profile_dir_size_mb "$target")"

    if [ -d "$target" ] && [ "${target_mb:-0}" -ge 5 ] && [ "${target_mb:-0}" -ge "${legacy_mb:-0}" ]; then
        _stop_cursor_profile_procs_soft
        bak="$HOME/Library/Application Support/ClaudeServerCursorProfile.bak-keep-$(date +%Y%m%d)"
        if [ ! -e "$bak" ]; then
            mv "$legacy" "$bak" 2>/dev/null || true
        fi
        mkdir -p "$target"
        printf 'ts=%s action=target_kept legacy_mb=%s target_mb=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$legacy_mb" "$target_mb" >"$stamp" 2>/dev/null || true
        declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROFILE_MIGRATE action=target_kept site=$site legacy_mb=$legacy_mb target_mb=$target_mb" 'INFO'
        return 0
    fi

    if [ -d "$target" ] && [ "${target_mb:-0}" -ge 5 ] && [ "${legacy_mb:-0}" -le "${target_mb:-0}" ]; then
        return 0
    fi

    _stop_cursor_profile_procs_soft
    if [ -d "$target" ]; then
        bak="$HOME/Library/Application Support/ClaudeServerCursorProfile-${site}.bak-pre-migrate-$(date +%Y%m%d%H%M%S)"
        mv "$target" "$bak" 2>/dev/null || true
    fi
    if mv "$legacy" "$target" 2>/dev/null; then
        :
    else
        mkdir -p "$target"
        # Best-effort copy+remove if rename across volumes fails
        cp -a "$legacy/." "$target/" 2>/dev/null || true
        rm -rf "$legacy" 2>/dev/null || true
    fi
    mkdir -p "$target"
    target_mb="$(_cursor_profile_dir_size_mb "$target")"
    printf 'ts=%s action=rename_legacy_to_target legacy_mb=%s final_mb=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$legacy_mb" "$target_mb" >"$stamp" 2>/dev/null || true
    declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROFILE_MIGRATE action=legacy_to_target site=$site legacy_mb=$legacy_mb final_mb=$target_mb" 'INFO'
    return 0
}

get_cursor_server_profile_dir() {
    ensure_cursor_remote_profile_migrated
    site="$(get_cursor_remote_profile_site)"
    if [ "$site" = "Sepidz" ]; then
        printf '%s' "$HOME/Library/Application Support/ClaudeServerCursorProfile-Sepidz"
    else
        printf '%s' "$HOME/Library/Application Support/ClaudeServerCursorProfile-Smart"
    fi
}

get_code_server_profile_dir() {
    printf '%s' "$HOME/Library/Application Support/ClaudeServerCodeProfile"
}



cursor_profile_process_count() {
    local profile_dir n=0 cmd line
    profile_dir="$(get_cursor_server_profile_dir)"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *"$profile_dir"*) n=$(( n + 1 )) ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    printf '%s' "$n"
}

test_may_clear_cursor_proxy_settings() {
    local allow="${1:-0}"
    if [ -n "${CURSOR_PROXY_OWNER:-}" ] && [ "${CURSOR_PROXY_OWNER}" = "0" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR_SKIP: reason=non_owner' 'WARN'
        return 1
    fi
    local n
    n="$(cursor_profile_process_count)"
    if [ "${n:-0}" -gt 0 ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open' 'WARN'
        return 1
    fi
    if [ "$allow" != "1" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR_SKIP: reason=no_allow_clear' 'DEBUG'
        return 1
    fi
    return 0
}

_resolve_cursor_proxy_ports() {
    # stdout: socks_port http_port (for CLI and settings).
    # Only advertise front doors when they listen AND backend -L is up; otherwise
    # return empty so launch skips --proxy-server (server_direct last resort).
    local front_s="${CURSOR_SOCKS_FRONT_PORT:-}" front_h="${CURSOR_HTTP_FRONT_PORT:-}"
    local back_s="${SOCKS_PROXY_PORT:-}" back_h="${HTTP_PROXY_PORT:-}"
    local socks="" http=""
    local front_up=0 back_up=0
    if [ -n "$back_s" ] && [ -n "$back_h" ]; then
        if declare -F test_local_port_open >/dev/null 2>&1; then
            if test_local_port_open "$back_s" && test_local_port_open "$back_h"; then
                back_up=1
            fi
        else
            back_up=1
        fi
    fi
    if [ -n "$front_s" ] && [ -n "$front_h" ] && declare -F test_local_port_open >/dev/null 2>&1; then
        if test_local_port_open "$front_s" && test_local_port_open "$front_h"; then
            front_up=1
        fi
    fi
    if [ "$front_up" -eq 1 ] && [ "$back_up" -eq 1 ]; then
        socks="$front_s"
        http="$front_h"
    elif [ "$back_up" -eq 1 ]; then
        socks="$back_s"
        http="$back_h"
    fi
    printf '%s %s' "${socks:-}" "${http:-}"
}

set_cursor_proxy_settings() {
    local socks_port="${1:-}" http_port="${2:-${HTTP_PROXY_PORT:-}}" profile settings proxy_url changed_out resolved
    resolved="$(_resolve_cursor_proxy_ports)"
    socks_port="${resolved%% *}"
    http_port="${resolved#* }"
    if [ -n "$http_port" ]; then
        proxy_url="http://127.0.0.1:${http_port}"
    elif [ -n "$socks_port" ]; then
        # Never write socks5 into settings.json (Node/MCP rejects it). CLI keeps socks5.
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "CURSOR_PROXY_SET: skip_settings no_http_leg socks=${socks_port} (CLI socks only)" 'WARN'
        fi
        return 1
    else
        return 1
    fi
    command -v python3 >/dev/null 2>&1 || return 1
    profile="$(get_cursor_server_profile_dir)"
    settings="$profile/User/settings.json"
    mkdir -p "$profile/User" 2>/dev/null || true
    changed_out="$(python3 - "$settings" "$proxy_url" <<'PY'
import json, sys
path, proxy_url = sys.argv[1], sys.argv[2]
keys = {
    "http.proxy": proxy_url,
    "https.proxy": proxy_url,
    "http.proxyStrictSSL": False,
    "http.proxySupport": "override",
    "cursor.general.proxyMode": "custom",
    "cursor.general.disableHttp2": True,
}
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    data = {}
changed = False
for key, val in keys.items():
    if data.get(key) != val:
        data[key] = val
        changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("1")
PY
)"
    if [ "$changed_out" = "1" ] && declare -F connect_log >/dev/null 2>&1; then
        connect_log "CURSOR_PROXY_SET: proxy=$proxy_url changed=1" 'INFO'
    fi
    [ "$changed_out" = "1" ]
}

cursor_proxy_settings_paths_for_clear() {
    # Personal Cursor + server-profile settings (dead sticky 18998 in either tree).
    local profile personal
    profile="$(get_cursor_server_profile_dir)/User/settings.json"
    personal="${HOME}/Library/Application Support/Cursor/User/settings.json"
    printf '%s\n' "$profile"
    if [ "$personal" != "$profile" ]; then
        printf '%s\n' "$personal"
    fi
}

clear_cursor_proxy_settings() {
    local settings changed_out any=0
    command -v python3 >/dev/null 2>&1 || return 1
    while IFS= read -r settings; do
        [ -n "$settings" ] || continue
        [ -f "$settings" ] || continue
        changed_out="$(python3 - "$settings" <<'PY'
import json, sys
path = sys.argv[1]
keys = [
    "http.proxy",
    "https.proxy",
    "http.proxyStrictSSL",
    "http.proxySupport",
    "cursor.general.proxyMode",
    "cursor.general.disableHttp2",
]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    sys.exit(0)
changed = False
for key in keys:
    if key in data:
        del data[key]
        changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("1")
PY
)"
        if [ "$changed_out" = "1" ]; then
            any=1
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "CURSOR_PROXY_CLEAR removed_18998_dead_proxy path=${settings}" 'WARN'
            fi
        fi
    done < <(cursor_proxy_settings_paths_for_clear)
    [ "$any" = "1" ]
}

remote_editor_running() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"
    remote_editor_on_correct_folder "$editor_cmd" "$alias_name" "$remote_path" \
        || remote_editor_window_open "$editor_cmd" "$alias_name" "$remote_path"
}

remote_editor_window_open() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"
    local profile_tag="" cmd line
    case "$editor_cmd" in
        cursor) profile_tag="$(basename "$(get_cursor_server_profile_dir)")" ;;
        code)   profile_tag="ClaudeServerCodeProfile" ;;
        *) return 1 ;;
    esac
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *--type=*) continue ;; esac
        case "$cmd" in *"$profile_tag"*) return 0 ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    return 1
}

# True when a profile main process has the correct folder-uri / path.
# IMPORTANT: require the full remote_path - matching only ssh-remote+ALIAS is wrong when
# several server users share the same alias (e.g. /home/smart/... vs /home/mohammad/...).
remote_editor_on_correct_folder() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"
    local profile_tag="" path_needle cmd line
    path_needle="${remote_path%/}"
    case "$editor_cmd" in
        cursor) profile_tag="$(basename "$(get_cursor_server_profile_dir)")" ;;
        code)   profile_tag="ClaudeServerCodeProfile" ;;
        *) return 1 ;;
    esac
    # Agent home is NOT correct-folder
    if [ "$editor_cmd" = "cursor" ] && remote_editor_in_agent_home "$alias_name" "$remote_path"; then
        return 1
    fi
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *--type=*) continue ;; esac
        case "$cmd" in *"$profile_tag"*) ;; *) continue ;; esac
        case "$cmd" in *"$path_needle"*) return 0 ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    return 1
}

# Match Windows Test-RemoteEditorInAgentHome: URI-less profile main only.
# Wrong-folder (has folder-uri to another path) is NOT agent home - use --new-window, do not soft-kill.
remote_editor_in_agent_home() {
    local alias_name="$1" remote_path="$2"
    local profile_tag="$(basename "$(get_cursor_server_profile_dir)")" cmd line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *--type=*) continue ;; esac
        case "$cmd" in *"$profile_tag"*)
            # URI-less profile main only.
            if [[ "$cmd" != *folder-uri* ]]; then return 0; fi
        ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    return 1
}

cursor_profile_main_count() {
    local profile_tag="$(basename "$(get_cursor_server_profile_dir)")" n=0 cmd line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *--type=*) continue ;; esac
        case "$cmd" in *"$profile_tag"*) n=$(( n + 1 )) ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    printf '%s' "$n"
}

# Soft-stop profile tree (used before --new-window relaunch from Agent home).
stop_cursor_profile_soft() {
    local profile_tag="$(basename "$(get_cursor_server_profile_dir)")" line pid cmd
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        pid="${line%% *}"
        cmd="${line#* }"
        case "$cmd" in *"$profile_tag"*) kill "$pid" 2>/dev/null || true ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    sleep 1
}

launch_remote_editor() {
    local cmd="$1" alias="$2" remote_path="$3" known_on_folder="${4:-0}"
    local uri profile use_new=0 agent_home=0 on_folder=0 profile_main=0
    local _cursor_bin _code_bin
    uri="vscode-remote://ssh-remote+${alias}${remote_path}"

    if [ "$cmd" = "cursor" ]; then
        profile="$(get_cursor_server_profile_dir)"
        mkdir -p "$profile/User" 2>/dev/null || true
        if declare -F init_cursor_server_profile >/dev/null 2>&1; then
            init_cursor_server_profile
        fi

        local _proxy_socks _proxy_http _is_owner=1 _launch_mode=none_direct
        if [ -n "${CURSOR_PROXY_OWNER:-}" ] && [ "${CURSOR_PROXY_OWNER}" = "0" ]; then
            _is_owner=0
        fi
        read -r _proxy_socks _proxy_http <<EOF
$(_resolve_cursor_proxy_ports)
EOF

        # Write proxy settings but NEVER soft-stop (preserves N open windows).
        # Only SET when resolve returned a healthy path; else CLEAR dead 18998.
        if [ "$_is_owner" -eq 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_SET_SKIP: reason=non_owner' 'DEBUG'
        elif [ -n "${_proxy_socks:-}" ] && [ -n "${_proxy_http:-}" ]; then
            if set_cursor_proxy_settings "$_proxy_socks" "$_proxy_http"; then
                declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_SET: preserved_open_windows socks=${_proxy_socks:-} http=${_proxy_http:-} (no soft-stop)" 'INFO'
            fi
            if declare -F get_cursor_proxy_mode >/dev/null 2>&1; then
                _launch_mode="$(get_cursor_proxy_mode)"
            else
                _launch_mode=sidecar
            fi
        else
            declare -F connect_log >/dev/null 2>&1 && \
                connect_log 'CURSOR_PROXY_CLEAR force reason=18998_down_or_unhealthy' 'WARN'
            if test_may_clear_cursor_proxy_settings 1; then
                if clear_cursor_proxy_settings; then
                    declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR: no_windows (no soft-stop)' 'INFO'
                fi
            else
                declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open_or_non_owner action=reload_for_server_direct' 'WARN'
            fi
            _launch_mode=server_direct
        fi

        # Chromium flags: Cursor 3.9.x always-local-singleton can ignore settings.json proxy.
        # No healthy socks => launch WITHOUT --proxy-server (server_direct last resort).
        _proxy_args=()
        if [ -n "$_proxy_socks" ]; then
            _proxy_args=(--proxy-server="socks5://127.0.0.1:${_proxy_socks}" --disable-http2)
            declare -F connect_log >/dev/null 2>&1 && connect_log "LAUNCH_PROXY mode=${_launch_mode} socks=${_proxy_socks}" 'INFO'
        else
            declare -F connect_log >/dev/null 2>&1 && connect_log "LAUNCH_PROXY mode=${_launch_mode:-server_direct}" 'INFO'
        fi

        if [ "$known_on_folder" = "1" ]; then
            on_folder=1
        else
            remote_editor_on_correct_folder cursor "$alias" "$remote_path" && on_folder=1
        fi
        remote_editor_in_agent_home "$alias" "$remote_path" && agent_home=1
        profile_main="$(cursor_profile_main_count)"
        local profile_all
        profile_all="$(cursor_profile_process_count)"

        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAUNCH_BEGIN editor=cursor on_folder=$on_folder agent_home=$agent_home profile_main=$profile_main profile_all=$profile_all auth_relaunch=${CURSOR_AUTH_RELAUNCH:-0}"
        fi

        if [ "${CURSOR_AUTH_RELAUNCH:-0}" = "1" ] && [ "${profile_all:-0}" -gt 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log "LAUNCH_KILL_SKIP: reason=auth_relaunch_never_kill profile_count=$profile_all main=$profile_main" 'WARN'
        fi

        if [ "$on_folder" -eq 1 ] && [ "$agent_home" -eq 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_SKIP: already on correct folder'
            return 0
        fi

        # Match Windows: new window when agent home or profile already open; do NOT soft-kill on agent_home.
        if [ "$agent_home" -eq 1 ] || [ "$profile_main" -gt 0 ]; then
            use_new=1
        fi

        _cursor_bin="$(_editor_run_cmd cursor)" || _cursor_bin=cursor
        if [ "$use_new" -eq 1 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_PLAN: --new-window'
            # Prefer classic+new-window, fall back to folder-uri
            "$_cursor_bin" --user-data-dir "$profile" "${_proxy_args[@]}" --new-window --classic --folder-uri "$uri" >/dev/null 2>&1 &
            sleep 0.8
            if ! remote_editor_on_correct_folder cursor "$alias" "$remote_path"; then
                "$_cursor_bin" --user-data-dir "$profile" "${_proxy_args[@]}" --new-window --folder-uri "$uri" >/dev/null 2>&1 &
            fi
        else
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_PLAN: cold --reuse-window'
            "$_cursor_bin" --user-data-dir "$profile" "${_proxy_args[@]}" --reuse-window --folder-uri "$uri" >/dev/null 2>&1 &
        fi
        return 0
    fi

    profile="$(get_code_server_profile_dir)"
    mkdir -p "$profile/User" 2>/dev/null || true
    _code_bin="$(_editor_run_cmd code)" || _code_bin=code
    if remote_editor_on_correct_folder code "$alias" "$remote_path"; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_SKIP: VS Code already on folder'
        return 0
    fi
    if remote_editor_window_open code "$alias" "$remote_path"; then
        "$_code_bin" --user-data-dir "$profile" --new-window --folder-uri "$uri" >/dev/null 2>&1 &
    else
        "$_code_bin" --user-data-dir "$profile" --reuse-window --folder-uri "$uri" >/dev/null 2>&1 &
    fi
}

test_personal_cursor_dominant() {
    local profile_dir personal_main profile_main line cmd
    profile_dir="$(get_cursor_server_profile_dir)"
    personal_main=0
    profile_main=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *--type=*) continue ;; esac
        case "$cmd" in *Cursor*|*cursor*)
            case "$cmd" in *"$profile_dir"*) profile_main=$(( profile_main + 1 )) ;;
            *) personal_main=$(( personal_main + 1 )) ;;
            esac
        ;; esac
    done < <(ps ax -o command= 2>/dev/null || true)
    [ "$personal_main" -ge 3 ] && [ "$profile_main" -eq 0 ]
}
