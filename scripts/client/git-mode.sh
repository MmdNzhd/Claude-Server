# git-mode.sh — shared GIT_MODE helpers (sourced by connect.sh forks)
# Requires: CFG_DIR, CM, PORT, LAPTOP_USER; functions sshx, warn; optional bg_pid + _tunnel_alive

GIT_CONF="$CFG_DIR/git.conf"

get_git_mode() {
    local saved="hide"
    if [ -f "$GIT_CONF" ]; then
        saved="$(tr '[:upper:]' '[:lower:]' < "$GIT_CONF" | tr -d '[:space:]')"
    fi
    case "$saved" in
        server|on|yes|1|slow) echo server ;;
        *) echo hide ;;
    esac
}

get_active_mount_id() {
    local line
    line="$(sshx "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null" 2>/dev/null | tail -1 || true)"
    line="${line#ACTIVE_MOUNT=}"
    line="${line//$'\r'/}"
    line="${line//$'\n'/}"
    printf '%s' "$line"
}

get_git_mode_label() {
    case "${1:-hide}" in
        server|slow) printf 'SLOW' ;;
        *) printf 'FAST' ;;
    esac
}

push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    mode="$(get_git_mode)"
    sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=%s\nACTIVE_MOUNT=%s\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf" 2>/dev/null || true
}

unmount_other_projects() {
    local keep="${1:-}"
    [ -n "$keep" ] || return 0
    sshx "$CM down-others '$keep'" 2>/dev/null || true
}

resolve_server_script_dir() {
    local script_dir="$1" _rel _candidate d i
    for _rel in "../server" "../../server" "../../../server"; do
        _candidate="$(cd "$script_dir/$_rel" 2>/dev/null && pwd)" || continue
        if [ -f "$_candidate/claude-mount.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
    done
    d="$script_dir"
    i=0
    while [ "$i" -lt 8 ] && [ -n "$d" ] && [ "$d" != "/" ]; do
        _candidate="$d/scripts/server"
        if [ -f "$_candidate/claude-mount.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
        _candidate="$d/server"
        if [ -f "$_candidate/claude-mount.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
        d="$(dirname "$d")"
        i=$((i + 1))
    done
    return 1
}

stop_remote_editor() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"
    local uri_needle="ssh-remote+${alias_name}" path_needle="${remote_path%/}"
    local profile="" line pid cmd found=0

    [ "$editor_cmd" = "cursor" ] && profile="$(get_cursor_remote_profile_dir)"

    _stop_remote_editor_pass() {
        local force="${1:-0}"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            pid="${line%% *}"
            cmd="${line#* }"
            case "$cmd" in *"$uri_needle"*) ;; *) continue ;; esac
            case "$cmd" in *"$path_needle"*) ;; *) continue ;; esac
            if [ -n "$profile" ]; then
                case "$cmd" in *"$profile"*) ;; *) continue ;; esac
            fi
            found=1
            if [ "$force" -eq 1 ]; then
                kill -9 "$pid" 2>/dev/null || true
            else
                kill "$pid" 2>/dev/null || true
            fi
        done < <(ps ax -o pid=,command= 2>/dev/null || true)
    }

    _stop_remote_editor_pass 0
    [ "$found" -eq 1 ] && sleep 2
    _stop_remote_editor_pass 1
}

clear_session_mount() {
    local project_id="$1" editor_cmd="${2:-}" alias_name="${3:-}" remote_path="${4:-}" skip_editor="${5:-0}"
    if [ "$skip_editor" != "1" ] && [ -n "$editor_cmd" ] && [ -n "$alias_name" ] && [ -n "$remote_path" ]; then
        stop_remote_editor "$editor_cmd" "$alias_name" "$remote_path"
    fi
    if [ -n "$project_id" ]; then
        timeout 8 ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$project_id'" 2>/dev/null || true
    fi
    ACTIVE_MOUNT_ID=""
    push_server_connect_conf
}

initialize_server_session() {
    local script_dir="$1"
    local port_base="${CONNECT_PORT_BASE:-20000}"
    local port_min="$port_base" _init uid_str pub_b server_dir
    local src="" git_src="" scp_pids="" push_ok=1 pid _chmod

    _init="$(sshx "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub" 2>/dev/null)"
    uid_str="$(printf '%s\n' "$_init" | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
    pub_b="$(printf '%s\n' "$_init" | tr -d '\r' | grep '^ssh-' | head -1)"
    PORT=$(( port_base + ${uid_str:-0} ))
    if [ "$PORT" -le "$port_min" ] || [ "$PORT" -gt 65535 ] || [ -z "$pub_b" ]; then
        return 1
    fi
    PUB_B="$pub_b"

    server_dir="$(resolve_server_script_dir "$script_dir" 2>/dev/null || true)"
    if [ -n "$server_dir" ]; then
        [ -f "$server_dir/claude-mount.sh" ] && src="$server_dir/claude-mount.sh"
        [ -f "$server_dir/claude-git-setup.sh" ] && git_src="$server_dir/claude-git-setup.sh"
        sshx "mkdir -p ~/.local/bin" 2>/dev/null || true
        if [ -n "$src" ]; then
            scp -o BatchMode=yes -o ConnectTimeout=30 -q "$src" "$ALIAS:~/.local/bin/claude-mount" &
            scp_pids="$scp_pids $!"
        fi
        if [ -n "$git_src" ]; then
            scp -o BatchMode=yes -o ConnectTimeout=30 -q "$git_src" "$ALIAS:~/.local/bin/claude-git-setup" &
            scp_pids="$scp_pids $!"
        fi
    fi

    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    grep -vF "$pub_b" "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" 2>/dev/null \
        && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys" || true
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo "from=\"127.0.0.1,::1\" $pub_b" >> "$HOME/.ssh/authorized_keys"

    awk -v a="$ALIAS" '
        /^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i==a) skip=1 }
        !skip
    ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${ALIAS}" 2>/dev/null \
        && mv "$HOME/.ssh/config.tmp.${ALIAS}" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    cat >> "$HOME/.ssh/config" <<EOF

Host $ALIAS
    HostName $SERVER_IP
    User $REMOTE_USER
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    RemoteForward $PORT localhost:22
    ExitOnForwardFailure no
EOF
    push_server_connect_conf

    for pid in $scp_pids; do
        [ -z "$pid" ] && continue
        wait "$pid" 2>/dev/null || push_ok=0
    done
    if [ -n "$server_dir" ] && { [ -n "$src" ] || [ -n "$git_src" ]; }; then
        _chmod=""
        [ -n "$src" ] && _chmod="chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc"
        [ -n "$git_src" ] && _chmod="${_chmod:+"$_chmod; "}chmod +x ~/.local/bin/claude-git-setup"
        [ -n "$_chmod" ] && sshx "$_chmod" 2>/dev/null || true
    fi

    [ "$push_ok" -eq 1 ]
}

configure_git_mode() {
    local cur choice cur_label saved_label
    cur="$(get_git_mode)"
    cur_label="$(get_git_mode_label "$cur")"
    echo ""
    printf '    \033[1;37mGit on server (SSHFS)\033[0m\n\n'
    if [ "$cur" = "server" ]; then
        printf '    \033[0;90mCurrent: %s (full git over SSHFS)\033[0m\n\n' "$cur_label"
    else
        printf '    \033[0;90mCurrent: %s (.git hidden on laptop)\033[0m\n\n' "$cur_label"
    fi
    printf '    \033[0;90m1  FAST - hide .git on laptop [default]\033[0m\n'
    printf '    \033[0;90m2  SLOW - keep .git on mount for git on server\033[0m\n\n'
    read -rp "    > " choice
    choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
    case "$choice" in
        1|off|hide|fast|"") printf 'hide\n' > "$GIT_CONF" ;;
        2|on|server|slow) printf 'server\n' > "$GIT_CONF" ;;
        *) warn "Invalid choice."; return ;;
    esac
    push_server_connect_conf
    echo ""
    saved_label="$(get_git_mode_label "$(get_git_mode)")"
    printf '    \033[0;32mSaved: git %s.\033[0m\n' "$saved_label"
    if [ -n "${ACTIVE_PROJECT_ID:-}" ]; then
        ACTIVE_MOUNT_ID="$ACTIVE_PROJECT_ID"
        push_server_connect_conf
        remount_project_git "$ACTIVE_PROJECT_ID"
    else
        printf '    \033[0;90mReconnect to apply on first mount.\033[0m\n'
    fi
    echo ""
}

show_mount_git_warn() {
    local out="$1" line
    line="$(printf '%s\n' "$out" | grep '^warn: git hide failed' | head -1 || true)"
    [ -n "$line" ] && warn "$line"
    line="$(printf '%s\n' "$out" | grep '^warn: laptop tunnel down' | head -1 || true)"
    [ -n "$line" ] && warn "$line"
}

test_mount_success() {
    local out="$1" ec="${2:-0}"
    echo "$out" | grep -qE 'error:|FAILED|No tunnel|not configured|unbound variable' && return 1
    [ "$ec" -eq 0 ] && return 0
    echo "$out" | grep -q 'already mounted:' && return 0
    return 1
}

read_retry_quit_key() {
    local timeout="${1:-30}" rk="" ki="" now
    local deadline=$(( $(date +%s) + timeout ))
    while [ "$rk" != r ] && [ "$rk" != q ]; do
        if read -r -t 1 -n 1 ki </dev/tty 2>/dev/null; then
            ki="$(printf '%s' "$ki" | tr '[:upper:]' '[:lower:]')"
            [ "$ki" = r ] && rk=r
            [ "$ki" = q ] && rk=q
        else
            now=$(date +%s)
            if [ "$now" -ge "$deadline" ]; then
                rk=q
                break
            fi
        fi
    done
    printf '%s' "$rk"
}

# When tunnel drops during session wait: honor buffered Q, else auto-reconnect.
# Sets globals: _action, _got_key (requires _tunnel_alive, bg_pid).
tunnel_drop_session_action() {
    if [ "${_got_key:-0}" -eq 0 ] && ! _tunnel_alive "$bg_pid"; then
        local _peek=""
        if read -r -t 0 -n 1 _peek </dev/tty 2>/dev/null; then
            local _pl
            _pl="$(printf '%s' "$_peek" | tr '[:upper:]' '[:lower:]')"
            if [ "$_pl" = "r" ]; then
                _action="r"
            else
                _action="q"
                _got_key=1
            fi
        else
            _action="r"
            printf '\n    Connection dropped - reconnecting...\n'
        fi
    fi
}

_git_mode_tunnel_ok() {
    if [ -n "${bg_pid:-}" ] && declare -F _tunnel_alive >/dev/null 2>&1; then
        _tunnel_alive "$bg_pid" && return 0
        return 1
    fi
    if declare -F tunnel_up >/dev/null 2>&1; then
        tunnel_up && return 0
        return 1
    fi
    return 0
}

remount_project_git() {
    local pid="$1"
    [ -n "$pid" ] || return 1
    echo ""
    printf '    \033[0;36mRemounting with git mode...\033[0m\n'
    sshx "$CM down '$pid'" 2>/dev/null || true
    printf '      -> recovering stale mounts...\n'
    sshx "$CM recover" 2>/dev/null || true
    if ! _git_mode_tunnel_ok; then
        warn "Tunnel dropped during remount - press R to reconnect"
        return 1
    fi
    local mount_out
    mount_out="$(sshx "$CM up '$pid' 2>&1")"
    show_mount_git_warn "$mount_out"
    if ! test_mount_success "$mount_out"; then
        warn "$(printf '%s' "$mount_out" | head -3)"
        return 1
    fi
    printf '    \033[0;32mGit mode: %s applied.\033[0m\n\n' "$(get_git_mode)"
    return 0
}

# Remote SSH Chat reads laptop Cursor globalStorage — pull golden tokens from server each connect.
get_cursor_remote_profile_dir() {
    # Isolated profile — separate from the developer's personal Cursor login (same as Windows).
    echo "$HOME/Library/Application Support/ClaudeServerCursorProfile"
}

init_cursor_server_profile() {
    local profile user_dir settings
    profile="$(get_cursor_remote_profile_dir)"
    user_dir="$profile/User"
    settings="$user_dir/settings.json"
    [ -f "$settings" ] && return 0
    mkdir -p "$user_dir"
    cat > "$settings" <<'JSON'
{
  "window.title": "${dirty}${activeEditorShort}${separator}[Claude Server] ${rootName}",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#1e3a5f",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "#152a45",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
JSON
}

resolve_remote_cursor_global_base() {
    local line cmd
    for cmd in \
        'cursor-auth-source-path 2>/dev/null' \
        'python3 /usr/local/lib/claude-server/cursor-auth-lib.py source-path 2>/dev/null'; do
        line="$(sshx "$cmd" 2>/dev/null | head -1 || true)"
        if [ -n "$line" ]; then
            printf '%s' "$line"
            return 0
        fi
    done
    line="$(sshx 'python3 -c "
import os, sqlite3
for rel in (\".config/Cursor/User/globalStorage\", \".config/cursor/User/globalStorage\", \".cursor-server/data/User/globalStorage\"):
    p = os.path.expanduser(\"~/\" + rel + \"/state.vscdb\")
    if not os.path.isfile(p):
        continue
    try:
        c = sqlite3.connect(p)
        a = c.execute(\"SELECT 1 FROM ItemTable WHERE key='"'"'cursorAuth/accessToken'"'"' LIMIT 1\").fetchone()
        r = c.execute(\"SELECT 1 FROM ItemTable WHERE key='"'"'cursorAuth/refreshToken'"'"' LIMIT 1\").fetchone()
        c.close()
        if a and r:
            print(rel)
            break
    except sqlite3.Error:
        pass
"' 2>/dev/null | head -1 || true)"
    if [ -n "$line" ]; then
        printf '%s' "$line"
        return 0
    fi
    return 1
}

local_cursor_auth_db_ok() {
    local db="$1"
    [ -f "$db" ] || return 1
    python3 - "$db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
try:
    c = sqlite3.connect(db)
    access = c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1").fetchone()
    refresh = c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/refreshToken' LIMIT 1").fetchone()
    c.close()
    sys.exit(0 if access and refresh else 1)
except sqlite3.Error:
    sys.exit(1)
PY
}

fetch_golden_auth_payload() {
    local payload cmd
    for cmd in \
        'python3 /usr/local/lib/claude-server/cursor-auth-lib.py laptop-auth-json 2>/dev/null' \
        'python3 -c "
import json, os
g = \"/etc/cursor-auth/golden\"
auth = json.load(open(os.path.join(g, \"auth.json\"), encoding=\"utf-8\"))
vals = {}
if auth.get(\"accessToken\"):
    vals[\"cursorAuth/accessToken\"] = auth[\"accessToken\"]
if auth.get(\"refreshToken\"):
    vals[\"cursorAuth/refreshToken\"] = auth[\"refreshToken\"]
if auth.get(\"cachedEmail\"):
    vals[\"cursorAuth/cachedEmail\"] = auth[\"cachedEmail\"]
sk = os.path.join(g, \"state-keys.json\")
if os.path.isfile(sk):
    vals.update(json.load(open(sk, encoding=\"utf-8\")))
mid = open(os.path.join(g, \"machine-id.txt\"), encoding=\"utf-8\").read().strip()
if mid:
    vals[\"storage.serviceMachineId\"] = mid
    for k in (\"telemetry.machineId\", \"telemetry.macMachineId\", \"telemetry.devDeviceId\", \"telemetry.sqmId\"):
        vals.setdefault(k, mid)
print(json.dumps(vals))
"'; do
        payload="$(sshx "$cmd" 2>/dev/null | tail -1 || true)"
        if [ -n "$payload" ] && printf '%s' "$payload" | grep -q 'cursorAuth/accessToken'; then
            printf '%s' "$payload"
            return 0
        fi
    done
    return 1
}

merge_cursor_auth_into_local_db() {
    local gs="$1" db="$gs/state.vscdb" payload="$2" attempt
    for attempt in 1 2 3 4 5; do
        if printf '%s' "$payload" | python3 - "$db" <<'PY'
import json, sqlite3, sys
db = sys.argv[1]
vals = json.loads(sys.stdin.read())
conn = sqlite3.connect(db, timeout=30)
conn.execute("PRAGMA busy_timeout=30000")
try:
    conn.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
    for k, v in vals.items():
        if v:
            conn.execute(
                "INSERT INTO ItemTable (key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (k, v),
            )
    conn.commit()
except sqlite3.Error:
    sys.exit(1)
finally:
    conn.close()
PY
        then
            return 0
        fi
        sleep 0.4
    done
    return 1
}

merge_cursor_storage_json_from_golden() {
    local gs="$1" dst="$gs/storage.json" src="$gs/storage.json.merge-src"
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$ALIAS:/etc/cursor-auth/golden/storage.json" "$src" 2>/dev/null || return 1
    python3 - "$src" "$dst" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
keys = [
    'telemetry.machineId', 'telemetry.macMachineId',
    'telemetry.devDeviceId', 'telemetry.sqmId',
]
try:
    with open(src, encoding='utf-8') as f:
        remote = json.load(f)
except (json.JSONDecodeError, OSError):
    sys.exit(1)
local = {}
if os.path.isfile(dst):
    try:
        with open(dst, encoding='utf-8') as f:
            data = json.load(f)
        if isinstance(data, dict):
            local = data
    except (json.JSONDecodeError, OSError):
        pass
for k in keys:
    if k in remote and remote[k]:
        local[k] = remote[k]
out = json.dumps(local, indent=2) + '\n'
tmp = dst + '.merge-tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(out)
os.replace(tmp, dst)
PY
    rm -f "$src"
}

sync_cursor_golden_auth() {
    sshx "test -f /etc/cursor-auth/golden/auth.json" 2>/dev/null || return 1
    sshx "cursor-auth-sync --force 2>&1" 2>/dev/null || true
    local gs payload
    gs="$(get_cursor_remote_profile_dir)/User/globalStorage"
    mkdir -p "$gs"
    payload="$(fetch_golden_auth_payload)" || return 1
    merge_cursor_auth_into_local_db "$gs" "$payload" || return 1
    merge_cursor_storage_json_from_golden "$gs" || true
    local_cursor_auth_db_ok "$gs/state.vscdb"
}

local_cursor_auth_complete() {
    local db="$1"
    python3 - "$db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
try:
    c = sqlite3.connect(db)
    a = c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1").fetchone()
    r = c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/refreshToken' LIMIT 1").fetchone()
    e = c.execute("SELECT 1 FROM ItemTable WHERE key='cursorAuth/cachedEmail' LIMIT 1").fetchone()
    c.close()
    sys.exit(0 if a and r and e else 1)
except sqlite3.Error:
    sys.exit(1)
PY
}

sync_cursor_golden_auth_status() {
    CURSOR_AUTH_SYNC_RESULT=fail
    sshx "test -f /etc/cursor-auth/golden/auth.json" 2>/dev/null || { CURSOR_AUTH_SYNC_RESULT=skipped; return 1; }
    sshx "cursor-auth-sync --force 2>&1" 2>/dev/null || true
    local gs payload db
    gs="$(get_cursor_remote_profile_dir)/User/globalStorage"
    mkdir -p "$gs"
    payload="$(fetch_golden_auth_payload)" || { CURSOR_AUTH_SYNC_RESULT=skipped; return 1; }
    merge_cursor_auth_into_local_db "$gs" "$payload" || { CURSOR_AUTH_SYNC_RESULT=fail; return 1; }
    merge_cursor_storage_json_from_golden "$gs" || true
    db="$gs/state.vscdb"
    if local_cursor_auth_complete "$db"; then
        CURSOR_AUTH_SYNC_RESULT=ok
        return 0
    fi
    if local_cursor_auth_db_ok "$db"; then
        CURSOR_AUTH_SYNC_RESULT=tokens_only
        return 0
    fi
    CURSOR_AUTH_SYNC_RESULT=fail
    return 1
}

push_cursor_golden_from_server_profile() {
    local gs db remote_dir msg
    gs="$(get_cursor_remote_profile_dir)/User/globalStorage"
    db="$gs/state.vscdb"
    if ! local_cursor_auth_complete "$db"; then
        printf 'Sign in inside [Claude Server] window first, then press P again'
        return 1
    fi
    remote_dir="/tmp/cursor-laptop-golden-$(whoami)-$$"
    sshx "mkdir -p '$remote_dir'" 2>/dev/null || return 1
    scp -o BatchMode=yes -o ConnectTimeout=20 -q \
        "$gs/auth.json" "$gs/state-keys.json" "$gs/storage.json" \
        "$ALIAS:$remote_dir/" 2>/dev/null || {
        sshx "rm -rf '$remote_dir'" 2>/dev/null || true
        printf 'Could not copy profile files to server'
        return 1
    }
    if ! ssh -t "$ALIAS" "sudo claude-server import-cursor-golden-laptop '$remote_dir'" 2>/dev/null; then
        sshx "rm -rf '$remote_dir'" 2>/dev/null || true
        printf 'Server import failed - run: sudo claude-server install'
        return 1
    fi
    sshx "rm -rf '$remote_dir'" 2>/dev/null || true
    sync_cursor_golden_auth_status || true
    printf 'Golden updated from [Claude Server] profile'
    return 0
}

get_last_project_id() {
    local f="$CFG_DIR/last.conf" line
    [ -f "$f" ] || return 0
    while IFS= read -r line; do
        case "$line" in
            LAST_PROJECT=*) printf '%s' "${line#LAST_PROJECT=}"; return 0 ;;
        esac
    done < "$f"
}

save_last_project_id() {
    printf 'LAST_PROJECT=%s\n' "$1" > "$CFG_DIR/last.conf" 2>/dev/null || true
}

read_post_disconnect_key() {
    local default="${1:-m}" timeout="${2:-10}" deadline key left
    deadline=$(( $(date +%s) + timeout ))
    echo ""
    printf '    \033[0;36mDisconnected. What would you like to do?\033[0m\n'
    printf '    \033[0;90mM = project menu   C = connect again   X = exit\033[0m\n\n'
    while [ "$(date +%s)" -lt "$deadline" ]; do
        left=$(( deadline - $(date +%s) ))
        printf '\r    Default %s in %ss...   ' "$default" "$left"
        if read -r -t 1 -n 1 key </dev/tty 2>/dev/null; then
            printf '\n'
            key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
            case "$key" in
                m) printf 'm'; return 0 ;;
                c) printf 'c'; return 0 ;;
                x) printf 'x'; return 0 ;;
            esac
        fi
    done
    printf '\n    Default %s\n' "$default"
    printf '%s' "$default"
}
