from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

# --- 1) mktemp fix ---
cui = root / 'scripts/client/connect-ui.sh'
t = cui.read_text(encoding='utf-8')
old = 'CONNECT_LOG_PATH="$(mktemp "${TMPDIR:-/tmp}/claude-connect.XXXXXX.log")"'
new = 'CONNECT_LOG_PATH="$(mktemp "${TMPDIR:-/tmp}/claude-connect.log.XXXXXX")"'
if old in t:
    t = t.replace(old, new)
    cui.write_text(t, encoding='utf-8', newline='\n')
    print('OK mktemp')
else:
    print('WARN mktemp', 'XXXXXX.log' in t)

# --- 2) ControlMaster in Mac sshx ---
cs = root / 'scripts/client/mac/connect.sh'
t = cs.read_text(encoding='utf-8')

if 'ControlMaster=auto' not in t:
    # After ALIAS/SERVER vars roughly - inject CM setup before sshx and modify sshx
    # Find sshx function and add CM opts
    old_ssh = '''sshx() {
    local orig_cmd="$*" remote_cmd ec=0 ms=0 trunc_cmd out b64
    # Base64-wrap so nested quotes survive Mac ssh → server.
    # Old: bash -lc '$esc' broke on any single quote (grep -E '^X=', ssh-keygen -N '', …)
    # and made warn_foreign_server_session show "unexpected EOF" instead of the real laptop name.
    if ! printf '%s' "$orig_cmd" | grep -qE '^[[:space:]]*timeout[[:space:]]'; then
        b64="$(printf '%s' "$orig_cmd" | base64 | tr -d '\\n\\r')"
        remote_cmd="timeout 45 bash -c \\"\\$(echo '$b64' | base64 -d)\\""
    else
        remote_cmd="$orig_cmd"
    fi
    if [ "${#orig_cmd}" -gt 200 ]; then trunc_cmd="${orig_cmd:0:200}..."; else trunc_cmd="$orig_cmd"; fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "SSH_BEGIN cmd=$trunc_cmd"
    fi
    local sw_start="$SECONDS"
    out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?
    ms=$(( (SECONDS - sw_start) * 1000 ))
    if [ "$ec" -eq 124 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "SSH_TIMEOUT exit=124 cmd=$trunc_cmd - retrying once" 'ERROR'
        fi
        sw_start="$SECONDS"
        out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\
            -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?
        ms=$(( (SECONDS - sw_start) * 1000 ))
    fi'''

    # Simpler: replace the two identical ssh invocation lines
    old_line = 'out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\\n        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?'
    # use exact from file
    t2 = t.replace(
        'ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\\n        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS"',
        'ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\\n        -o ControlMaster=auto -o ControlPath="${_SSH_CM_PATH}" -o ControlPersist=180 \\\n        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS"'
    )
    if t2 == t:
        # try single-line form
        t2 = t.replace(
            '-o BatchMode=yes -o ConnectTimeout=30 \\\n        -o ServerAliveInterval=10',
            '-o BatchMode=yes -o ConnectTimeout=30 \\\n        -o ControlMaster=auto -o ControlPath="${_SSH_CM_PATH}" -o ControlPersist=180 \\\n        -o ServerAliveInterval=10'
        )
    if t2 != t:
        t = t2
        # init CM path near top after CONNECT_VERSION
        needle = "CONNECT_PORT_BASE=20000\n"
        inject = needle + '\n# Reuse one SSH TCP connection for all sshx() calls this session (big speed win).\n_SSH_CM_DIR="${HOME}/.cache/claude-connect/cm"\nmkdir -p "$_SSH_CM_DIR" 2>/dev/null || true\n_SSH_CM_PATH="${_SSH_CM_DIR}/cm-%C"\n'
        if needle in t and '_SSH_CM_PATH' not in t.split('sshx()')[0]:
            t = t.replace(needle, inject, 1)
        print('OK ControlMaster sshx')
    else:
        print('WARN ControlMaster replace failed')
        idx = t.find('ConnectTimeout=30')
        print(repr(t[idx-80:idx+120]))
else:
    print('SKIP ControlMaster exists')

# cleanup CM on cleanup_session
if '_SSH_CM_PATH' in t and 'ControlPath=$_SSH_CM' not in t and 'ssh -O exit' not in t:
    # add to cleanup_session start
    old_c = 'cleanup_session() {\n    if declare -F log_session_context'
    new_c = 'cleanup_session() {\n    if [ -n "${_SSH_CM_PATH:-}" ]; then ssh -O exit -o ControlPath="${_SSH_CM_PATH}" "$ALIAS" >/dev/null 2>&1 || true; fi\n    if declare -F log_session_context'
    if old_c in t:
        t = t.replace(old_c, new_c, 1)
        print('OK CM cleanup')
    else:
        # looser
        m = re.search(r'cleanup_session\(\) \{\n(\s*)if declare -F log_session_context', t)
        if m:
            t = t[:m.start()] + 'cleanup_session() {\n' + m.group(1) + 'if [ -n "${_SSH_CM_PATH:-}" ]; then ssh -O exit -o ControlPath="${_SSH_CM_PATH}" "$ALIAS" >/dev/null 2>&1 || true; fi\n' + m.group(1) + 'if declare -F log_session_context' + t[m.end():]
            print('OK CM cleanup regex')
        else:
            print('WARN CM cleanup')

cs.write_text(t, encoding='utf-8', newline='\n')

# --- 3) WAL checkpoint after merge + stronger login hint ---
gm = root / 'scripts/client/git-mode.sh'
g = gm.read_text(encoding='utf-8')
old_merge_ok = '''        if cursor_sqlite_merge_pairs "$db" "$pairs_file"; then
            rm -f "$pairs_file"
            return 0
        fi'''
new_merge_ok = '''        if cursor_sqlite_merge_pairs "$db" "$pairs_file"; then
            sqlite3 "$db" "PRAGMA wal_checkpoint(FULL);" >/dev/null 2>&1 || true
            rm -f "$pairs_file"
            return 0
        fi'''
if old_merge_ok in g:
    g = g.replace(old_merge_ok, new_merge_ok, 1)
    print('OK wal checkpoint')
else:
    print('WARN wal')

gm.write_text(g, encoding='utf-8', newline='\n')

# --- 4) After Opening Cursor success, stronger auth hint ---
t = cs.read_text(encoding='utf-8')
hint = '''                        if [ "$EDITOR_CMD" = "cursor" ]; then
                            printf '      -> \\033[0;33mIf Cursor asks to log in: use the [Claude Server] window → Developer → Reload Window\\033[0m\\n'
                            printf '      -> \\033[0;90mDo NOT sign in with a personal account in that window\\033[0m\\n'
'''
# Find existing block after step_ok "$go_path" for cursor
if 'If Cursor asks to log in' not in t:
    old = '''                        step_ok "$go_path"
                        _did_launch=1
                        if [ "$EDITOR_CMD" = "cursor" ]; then'''
    # read actual next lines - insert after _did_launch=1
    needle = '                        _did_launch=1\n                        if [ "$EDITOR_CMD" = "cursor" ]; then'
    if needle in t:
        t = t.replace(needle, '''                        _did_launch=1
                        if [ "$EDITOR_CMD" = "cursor" ]; then
                            printf '      -> \\033[0;33mIf Cursor asks to log in: [Claude Server] window → Developer → Reload Window\\033[0m\\n'
                            printf '      -> \\033[0;90mDo NOT use a personal login in that window\\033[0m\\n'
''', 1)
        print('OK login hint')
    else:
        print('WARN login hint needle')
        idx = t.find('_did_launch=1')
        print(repr(t[idx:idx+200]))
else:
    print('SKIP login hint')

cs.write_text(t, encoding='utf-8', newline='\n')

# bump .27
for rel in [
    'scripts/client/mac/connect.sh',
    'scripts/client/windows/connect.ps1',
    'scripts/client/windows/connect-version.txt',
    'scripts/client/mac/connect-version.txt',
]:
    p = root / rel
    c = p.read_text(encoding='utf-8')
    for oldv in ('20260717.26', '20260717.25', '20260717.24', '20260717.22'):
        c = c.replace(oldv, '20260717.27')
    p.write_text(c, encoding='utf-8')
print('bumped .27')
