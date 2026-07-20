from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')

# --- Mac editor-launch.sh ---
sh_path = root / 'scripts/client/editor-launch.sh'
sh = sh_path.read_text(encoding='utf-8')

old = '''# True when a profile main process has the correct folder-uri / path.
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
}'''

new = '''# True when a profile main process has the correct folder-uri / path.
# IMPORTANT: require the full remote_path — matching only ssh-remote+ALIAS is wrong when
# several server users share the same alias (e.g. /home/smart/... vs /home/mohammad/...).
remote_editor_on_correct_folder() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"
    local profile_tag="" path_needle cmd line
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
    done < <(ps ax -o pid=,command= 2>/dev/null || true)
    return 1
}'''

if old not in sh:
    raise SystemExit('mac on_correct_folder block missing')
sh = sh.replace(old, new, 1)

# After auth sync in launch: if CURSOR_AUTH_JUST_SYNCED=1, soft-stop before launch
# Better: patch launch_remote_editor to soft-stop when env CURSOR_AUTH_RELAUNCH=1
old_launch = '''        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAUNCH_BEGIN editor=cursor on_folder=$on_folder agent_home=$agent_home profile_main=$profile_main"
        fi

        if [ "$on_folder" -eq 1 ] && [ "$agent_home" -eq 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_SKIP: already on correct folder'
            return 0
        fi'''

new_launch = '''        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAUNCH_BEGIN editor=cursor on_folder=$on_folder agent_home=$agent_home profile_main=$profile_main auth_relaunch=${CURSOR_AUTH_RELAUNCH:-0}"
        fi

        # Auth just written to disk — must not reuse a long-lived logged-out process.
        if [ "${CURSOR_AUTH_RELAUNCH:-0}" = "1" ] && [ "$profile_main" -gt 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_KILL: auth_relaunch soft-stop profile'
            stop_cursor_profile_soft
            on_folder=0
            agent_home=0
            profile_main=0
        fi

        if [ "$on_folder" -eq 1 ] && [ "$agent_home" -eq 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && connect_log 'LAUNCH_SKIP: already on correct folder'
            return 0
        fi'''

if old_launch not in sh:
    raise SystemExit('mac launch begin block missing')
sh = sh.replace(old_launch, new_launch, 1)
sh_path.write_bytes(sh.replace('\r\n','\n').replace('\r','\n').encode())
print('OK editor-launch.sh')

# --- Mac connect.sh: set CURSOR_AUTH_RELAUNCH after auth sync ---
cs = root / 'scripts/client/mac/connect.sh'
ct = cs.read_text(encoding='utf-8')
# Find sync_cursor_golden_auth_status case ok
if 'CURSOR_AUTH_RELAUNCH' not in ct:
    old_auth = '''                    sync_cursor_golden_auth_status
                    case "$CURSOR_AUTH_SYNC_RESULT" in
                        ok) step_ok; _last_auth_detail='ok'; date -u +%Y-%m-%dT%H:%M:%SZ > "$CFG_DIR/cursor-auth.ok" 2>/dev/null || true ;;'''
    # read actual
    idx = ct.find('sync_cursor_golden_auth_status')
    print('AUTH CONTEXT:\n', ct[idx:idx+500])
else:
    print('connect already has RELAUNCH')

# Windows editor-launch.ps1 - find OnCorrectFolder
ps = root / 'scripts/client/editor-launch.ps1'
pt = ps.read_text(encoding='utf-8')
idx = pt.find('OnCorrectFolder')
# find function Test-RemoteEditorOnCorrectFolder or similar
import re
m = re.search(r'function\s+(\w*[Oo]n[Cc]orrect\w*)', pt)
print('win function', m.group(1) if m else None)
if m:
    start = m.start()
    print(pt[start:start+1200])
