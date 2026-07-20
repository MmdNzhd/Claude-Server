from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
files = [
    root / 'scripts/client/mac/connect.sh',
    root / 'scripts/client/connect-ui.sh',
    root / 'scripts/client/git-mode.sh',
    root / 'scripts/client/mac/connect-version.txt',
]

for p in files:
    raw = p.read_bytes()
    cr = raw.count(b'\r')
    if cr:
        text = raw.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
        p.write_bytes(text)
        print('LF fixed:', p.name, 'CR removed:', cr)
    else:
        print('OK LF:', p.name)

cs = root / 'scripts/client/mac/connect.sh'
t = cs.read_text(encoding='utf-8')

old_retry = (
    '        out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\\n'
    '            -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?'
)
new_retry = (
    '        out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \\\n'
    '            -o ControlMaster=auto -o ControlPath="${_SSH_CM_PATH}" -o ControlPersist=180 \\\n'
    '            -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?'
)
if old_retry in t:
    t = t.replace(old_retry, new_retry, 1)
    print('OK retry ControlMaster')
else:
    print('WARN retry replace')

old_cu = (
    '        cleanup_session() {\n'
    '    if [ -n "${_SSH_CM_PATH:-}" ]; then ssh -O exit -o ControlPath="${_SSH_CM_PATH}" "$ALIAS" >/dev/null 2>&1 || true; fi\n'
    '    if declare -F log_session_context >/dev/null 2>&1; then log_session_context \'cleanup\'; fi\n'
    '    if declare -F flush_connect_log_to_server >/dev/null 2>&1; then flush_connect_log_to_server || true; fi\n'
    '            if [ "$already_down" -eq 0 ]; then'
)
new_cu = (
    '        cleanup_session() {\n'
    '            if [ -n "${_SSH_CM_PATH:-}" ]; then ssh -O exit -o ControlPath="${_SSH_CM_PATH}" "$ALIAS" >/dev/null 2>&1 || true; fi\n'
    '            if declare -F log_session_context >/dev/null 2>&1; then log_session_context \'cleanup\'; fi\n'
    '            if declare -F flush_connect_log_to_server >/dev/null 2>&1; then flush_connect_log_to_server || true; fi\n'
    '            if [ "$already_down" -eq 0 ]; then'
)
if old_cu in t:
    t = t.replace(old_cu, new_cu, 1)
    print('OK cleanup indent')
else:
    print('WARN cleanup indent')

cs.write_bytes(t.replace('\r\n', '\n').replace('\r', '\n').encode('utf-8'))

claude = root / 'CLAUDE.md'
c = claude.read_text(encoding='utf-8')
c2 = c.replace('20260717.24', '20260717.27')
if c2 != c:
    claude.write_text(c2.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
    print('OK CLAUDE.md')
else:
    print('SKIP CLAUDE.md')

print('done')
