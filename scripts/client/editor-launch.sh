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

resolve_editor_choice() {
    local cfg="$1" pref have_cursor="" have_code=""
    command -v cursor >/dev/null 2>&1 && have_cursor=1
    command -v code   >/dev/null 2>&1 && have_code=1
    if [ -z "$have_cursor" ] && [ -z "$have_code" ]; then
        return 1
    fi
    if [ -n "$have_cursor" ] && [ -z "$have_code" ]; then
        EDITOR_CMD=cursor; EDITOR_NAME=Cursor; return 0
    fi
    if [ -z "$have_cursor" ] && [ -n "$have_code" ]; then
        EDITOR_CMD=code; EDITOR_NAME="VS Code"; return 0
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
            1|cursor|c) EDITOR_CMD=cursor; EDITOR_NAME=Cursor ;;
            2|code|vscode|v) EDITOR_CMD=code; EDITOR_NAME="VS Code" ;;
            "") [ "$saved" = "code" ] && { EDITOR_CMD=code; EDITOR_NAME="VS Code"; } \
                                      || { EDITOR_CMD=cursor; EDITOR_NAME=Cursor; } ;;
            *) EDITOR_CMD=cursor; EDITOR_NAME=Cursor ;;
        esac
        return 0
    fi
    if [ "$pref" = "code" ]; then
        EDITOR_CMD=code; EDITOR_NAME="VS Code"
    else
        EDITOR_CMD=cursor; EDITOR_NAME=Cursor
    fi
    return 0
}

get_cursor_server_profile_dir() {
    printf '%s' "$HOME/Library/Application Support/ClaudeServerCursorProfile"
}

get_code_server_profile_dir() {
    printf '%s' "$HOME/Library/Application Support/ClaudeServerCodeProfile"
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
        cursor) profile_tag="ClaudeServerCursorProfile" ;;
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
remote_editor_on_correct_folder() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"
    local profile_tag="" uri_needle path_needle cmd line
    uri_needle="ssh-remote+${alias_name}"
    path_needle="${remote_path%/}"
    case "$editor_cmd" in
        cursor) profile_tag="ClaudeServerCursorProfile" ;;
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
        case "$cmd" in *"$uri_needle"*) return 0 ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    return 1
}

# Cursor profile open but not on this project (Agent home / wrong workspace).
remote_editor_in_agent_home() {
    local alias_name="$1" remote_path="$2"
    local profile_tag="ClaudeServerCursorProfile" cmd line
    local has_profile_main=0 on_target=0
    local path_needle="${remote_path%/}"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *--type=*) continue ;; esac
        case "$cmd" in *"$profile_tag"*)
            has_profile_main=1
            case "$cmd" in *"$path_needle"*) on_target=1 ;; esac
        ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    [ "$has_profile_main" -eq 0 ] && return 1
    [ "$on_target" -eq 0 ] && return 0
    return 1
}

cursor_profile_main_count() {
    local profile_tag="ClaudeServerCursorProfile" n=0 cmd line
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
    local profile_tag="ClaudeServerCursorProfile" line pid cmd
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
    uri="vscode-remote://ssh-remote+${alias}${remote_path}"

    if [ "$cmd" = "cursor" ]; then
        profile="$(get_cursor_server_profile_dir)"
        mkdir -p "$profile/User" 2>/dev/null || true
        if declare -F init_cursor_server_profile >/dev/null 2>&1; then
            init_cursor_server_profile
        fi

        if [ "$known_on_folder" = "1" ]; then
            on_folder=1
        else
            remote_editor_on_correct_folder cursor "$alias" "$remote_path" && on_folder=1
        fi
        remote_editor_in_agent_home "$alias" "$remote_path" && agent_home=1
        profile_main="$(cursor_profile_main_count)"

        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAUNCH_BEGIN editor=cursor on_folder=$on_folder agent_home=$agent_home profile_main=$profile_main"
        fi

        if [ "$on_folder" -eq 1 ] && [ "$agent_home" -eq 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_SKIP: already on correct folder'
            return 0
        fi

        # Match Windows: new window when agent home or profile already open
        if [ "$agent_home" -eq 1 ] || [ "$profile_main" -gt 0 ]; then
            use_new=1
        fi
        if [ "$agent_home" -eq 1 ] && [ "$profile_main" -gt 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_KILL: agent_home soft-stop profile'
            stop_cursor_profile_soft
        fi

        if [ "$use_new" -eq 1 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_PLAN: --new-window'
            # Prefer classic+new-window, fall back to folder-uri
            cursor --user-data-dir "$profile" --new-window --classic --folder-uri "$uri" >/dev/null 2>&1 &
            sleep 0.8
            if ! remote_editor_on_correct_folder cursor "$alias" "$remote_path"; then
                cursor --user-data-dir "$profile" --new-window --folder-uri "$uri" >/dev/null 2>&1 &
            fi
        else
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_PLAN: cold --reuse-window'
            cursor --user-data-dir "$profile" --reuse-window --folder-uri "$uri" >/dev/null 2>&1 &
        fi
        return 0
    fi

    profile="$(get_code_server_profile_dir)"
    mkdir -p "$profile/User" 2>/dev/null || true
    if remote_editor_on_correct_folder code "$alias" "$remote_path"; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_SKIP: VS Code already on folder'
        return 0
    fi
    if remote_editor_window_open code "$alias" "$remote_path"; then
        code --user-data-dir "$profile" --new-window --folder-uri "$uri" >/dev/null 2>&1 &
    else
        code --user-data-dir "$profile" --reuse-window --folder-uri "$uri" >/dev/null 2>&1 &
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
