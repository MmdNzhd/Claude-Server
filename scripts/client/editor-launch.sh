# editor-launch.sh — shared VS Code/Cursor launch (sourced by connect.sh)

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
    printf '    \033[0;90m1  cursor — always open Cursor\033[0m\n'
    printf '    \033[0;90m2  code   — always open VS Code\033[0m\n'
    printf '    \033[0;90m3  ask    — pick each connect\033[0m\n\n'
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
    local profile_tag="" uri_needle path_needle cmd line

    uri_needle="ssh-remote+${alias_name}"
    path_needle="${remote_path%/}"
    case "$editor_cmd" in
        cursor) profile_tag="ClaudeServerCursorProfile" ;;
        code)   profile_tag="ClaudeServerCodeProfile" ;;
        *) return 1 ;;
    esac

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *"$profile_tag"*) ;; *) continue ;; esac
        case "$cmd" in *"$uri_needle"*) return 0 ;; esac
        case "$cmd" in *"$path_needle"*) return 0 ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        cmd="${line#* }"
        case "$cmd" in *"$profile_tag"*) return 0 ;; esac
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    return 1
}

launch_remote_editor() {
    local cmd="$1" alias="$2" remote_path="$3" uri profile
    uri="vscode-remote://ssh-remote+${alias}${remote_path}"
    if [ "$cmd" = "cursor" ]; then
        profile="$(get_cursor_server_profile_dir)"
        mkdir -p "$profile/User" 2>/dev/null || true
        cursor --user-data-dir "$profile" --reuse-window --folder-uri "$uri" >/dev/null 2>&1 &
    else
        profile="$(get_code_server_profile_dir)"
        mkdir -p "$profile/User" 2>/dev/null || true
        code --user-data-dir "$profile" --reuse-window --folder-uri "$uri" >/dev/null 2>&1 &
    fi
}
