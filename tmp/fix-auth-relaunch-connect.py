from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
cs = root / 'scripts/client/mac/connect.sh'
ct = cs.read_text(encoding='utf-8')

old = '''                        ok) step_ok; _last_auth_detail='ok'; date -u +%Y-%m-%dT%H:%M:%SZ > "$CFG_DIR/cursor-auth.ok" 2>/dev/null || true ;;
                        tokens_only)
                            step_ok "tokens only"
                            _last_auth_detail='tokens only'
                            warn 'Partial auth on laptop - reconnect; server auth is managed on server only'
                            ;;
                        skipped) step_ok "skipped"; _last_auth_detail='skipped' ;;'''

new = '''                        ok)
                            step_ok
                            _last_auth_detail='ok'
                            date -u +%Y-%m-%dT%H:%M:%SZ > "$CFG_DIR/cursor-auth.ok" 2>/dev/null || true
                            # Force fresh Cursor process so disk auth/machineid is loaded (not a weeks-old reuse-window).
                            export CURSOR_AUTH_RELAUNCH=1
                            ;;
                        tokens_only)
                            step_ok "tokens only"
                            _last_auth_detail='tokens only'
                            warn 'Partial auth on laptop - reconnect; server auth is managed on server only'
                            export CURSOR_AUTH_RELAUNCH=1
                            ;;
                        skipped)
                            step_ok "skipped"
                            _last_auth_detail='skipped'
                            export CURSOR_AUTH_RELAUNCH=1
                            ;;'''

if old not in ct:
    raise SystemExit('auth case block missing')
ct = ct.replace(old, new, 1)

# bump .31
ct = ct.replace('20260717.30', '20260717.31').replace('20260717.29', '20260717.31')
cs.write_bytes(ct.replace('\r\n','\n').replace('\r','\n').encode())
print('OK connect.sh')

for rel in [
    'scripts/client/windows/connect.ps1',
    'scripts/client/mac/connect-version.txt',
    'scripts/client/windows/connect-version.txt',
    'publish/README.txt',
    'publish/README-sepidz.txt',
    'CLAUDE.md',
]:
    p = root / rel
    c = p.read_text(encoding='utf-8')
    c2 = c.replace('20260717.30', '20260717.31').replace('20260717.29', '20260717.31')
    if c2 != c:
        p.write_text(c2, encoding='utf-8')
        print('bumped', rel)

# Ensure editor-launch LF
p = root / 'scripts/client/editor-launch.sh'
p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n').replace(b'\r', b'\n'))

# Verify Mac fixes present
el = (root/'scripts/client/editor-launch.sh').read_text(encoding='utf-8')
assert 'require the full remote_path' in el
assert 'CURSOR_AUTH_RELAUNCH' in el
assert 'uri_needle' not in el.split('remote_editor_on_correct_folder')[1].split('remote_editor_in_agent_home')[0] or 'uri_needle' not in el[el.find('remote_editor_on_correct_folder'):el.find('remote_editor_in_agent_home')+50]
# check uri_needle removed from on_correct_folder
block = el[el.find('remote_editor_on_correct_folder'):el.find('remote_editor_in_agent_home')]
assert 'uri_needle' not in block, block[:500]
assert 'CURSOR_AUTH_RELAUNCH' in (root/'scripts/client/mac/connect.sh').read_text(encoding='utf-8')
print('verified')
