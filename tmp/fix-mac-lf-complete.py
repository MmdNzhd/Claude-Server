from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
mac_dirs = [
    root / 'scripts/client',
    root / 'scripts/client/mac',
]
# All shell scripts that ship to Mac
targets = []
for d in mac_dirs:
    if not d.exists():
        continue
    for p in d.iterdir():
        if p.is_file() and p.suffix == '.sh':
            targets.append(p)
# Also shared sources deployed as mac/*
for name in ['git-mode.sh', 'connect-ui.sh', 'editor-launch.sh', 'claude-mount.sh']:
    p = root / 'scripts/client' / name
    if p.exists():
        targets.append(p)
# server copies under scripts/server that go to bundle
for name in ['claude-mount.sh']:
    p = root / 'scripts/server' / name
    if p.exists():
        targets.append(p)

seen = set()
fixed = 0
for p in targets:
    key = str(p.resolve())
    if key in seen:
        continue
    seen.add(key)
    raw = p.read_bytes()
    cr = raw.count(b'\r')
    if cr:
        p.write_bytes(raw.replace(b'\r\n', b'\n').replace(b'\r', b'\n'))
        print(f'FIXED {p.relative_to(root)} CR={cr}')
        fixed += 1
    else:
        print(f'OK    {p.relative_to(root)}')

# Version consistency
ver = '20260717.28'
checks = {
    'mac/connect.sh': "CONNECT_VERSION='20260717.28'",
    'windows/connect.ps1': "ConnectVersion = '20260717.28'",
    'mac/connect-version.txt': '20260717.28',
    'windows/connect-version.txt': '20260717.28',
}
for rel, needle in checks.items():
    p = root / 'scripts/client' / rel.replace('/', '\\') if False else root / 'scripts/client' / Path(rel)
    # Path handles both
    p = root / 'scripts' / 'client' / Path(*rel.split('/'))
    text = p.read_text(encoding='utf-8', errors='replace').replace('\r', '')
    print(('PASS' if needle in text else 'FAIL'), rel, '->', text.splitlines()[0][:60] if rel.endswith('.txt') else '...')

# Ensure Q-path + CM present
cs = (root / 'scripts/client/mac/connect.sh').read_text(encoding='utf-8')
for label, frag in [
    ('CM', 'ControlMaster=auto'),
    ('Q flush', "log_session_context 'session_end'"),
    ('mux exit', 'ssh -O exit'),
    ('login hint', 'If Cursor asks to log in'),
    ('early flush restore', "CONNECT_LOG_EARLY_FLUSH"),
]:
    # early flush restore might not have that comment - check trap restore
    ok = frag in cs
    if label == 'early flush restore':
        ok = "flush_connect_log_to_server || true; fi' EXIT" in cs and 'session_end' in cs
    print(('PASS' if ok else 'FAIL'), label)

ui = (root / 'scripts/client/connect-ui.sh').read_text(encoding='utf-8')
print(('PASS' if 'claude-connect.log.XXXXXX' in ui else 'FAIL'), 'mktemp')
gm = (root / 'scripts/client/git-mode.sh').read_text(encoding='utf-8')
print(('PASS' if 'wal_checkpoint(FULL)' in gm else 'FAIL'), 'wal')
print(('PASS' if 'access_ssh-disabled' in gm else 'FAIL'), 'access_ssh-disabled')
print(('PASS' if 'mac_ssh_clear_disabled' in gm or 'com.apple.access_ssh-disabled' in gm else 'FAIL'), 'disabled heal')

print('fixed_count', fixed)
