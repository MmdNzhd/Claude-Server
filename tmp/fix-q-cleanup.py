from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
cs = root / 'scripts/client/mac/connect.sh'
t = cs.read_text(encoding='utf-8')

old = '''        stop_session_tunnel_cleanup 1

        trap - EXIT SIGTERM SIGHUP
'''
new = '''        stop_session_tunnel_cleanup 1

        # Q / normal disconnect skips cleanup_session (already_down=1); still flush logs + close SSH mux.
        if declare -F log_session_context >/dev/null 2>&1; then log_session_context 'session_end'; fi
        if [ -n "${_SSH_CM_PATH:-}" ]; then ssh -O exit -o ControlPath="${_SSH_CM_PATH}" "$ALIAS" >/dev/null 2>&1 || true; fi
        if declare -F flush_connect_log_to_server >/dev/null 2>&1; then flush_connect_log_to_server || true; fi

        trap - EXIT SIGTERM SIGHUP
        # Menu / final exit still needs log upload (session trap was cleared).
        trap 'if declare -F flush_connect_log_to_server >/dev/null 2>&1; then flush_connect_log_to_server || true; fi' EXIT
'''
if old not in t:
    raise SystemExit('needle not found')
t = t.replace(old, new, 1)

# bump .27 -> .28
for rel in [
    'scripts/client/mac/connect.sh',
    'scripts/client/windows/connect.ps1',
    'scripts/client/windows/connect-version.txt',
    'scripts/client/mac/connect-version.txt',
    'publish/README.txt',
    'publish/README-sepidz.txt',
    'CLAUDE.md',
]:
    p = root / rel
    if not p.exists():
        continue
    c = p.read_text(encoding='utf-8')
    c2 = c.replace('20260717.27', '20260717.28')
    if c2 != c:
        p.write_text(c2, encoding='utf-8', newline='\n' if p.suffix in {'.sh', '.md', '.txt'} and 'windows' not in str(p) else None)
        # force LF for sh
        if p.suffix == '.sh' or p.name.endswith('.sh') or 'mac/connect' in str(p).replace('\\\\','/'):
            p.write_bytes(p.read_bytes().replace(b'\\r\\n', b'\\n').replace(b'\\r', b'\\n'))
        print('bumped', rel)
    else:
        # connect.sh still has .27 in CONNECT_VERSION from current t
        pass

# apply connect.sh with version bump
t = t.replace('20260717.27', '20260717.28')
cs.write_bytes(t.replace('\\r\\n', '\\n').replace('\\r', '\\n').encode('utf-8'))
print('OK connect.sh Q cleanup + .28')
