from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
gm = root / 'scripts/client/git-mode.sh'
t = gm.read_text(encoding='utf-8')

# Fix gold mid fetch in needs_refresh
old = '''    _gold_mid="$(sshx "tr -d \\"[:space:]\\" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null" 2>/dev/null | tr -d "\\r\\n" || true)"'''
# may already be different - find by marker
import re
m = re.search(r'_gold_mid="\$\(sshx.*?\)"', t, re.S)
if not m:
    # line based
    lines = t.splitlines()
    for i,l in enumerate(lines):
        if '_gold_mid=' in l:
            print('FOUND line', i+1, l)
            lines[i] = '''    _gold_mid="$(sshx 'tr -d "[:space:]" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null' 2>/dev/null | tr -d '\\r\\n' || true)"'''
            t = '\n'.join(lines) + ('\n' if t.endswith('\n') else '')
            print('replaced')
            break
    else:
        raise SystemExit('gold mid not found')
else:
    t = t[:m.start()] + '''_gold_mid="$(sshx 'tr -d "[:space:]" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null' 2>/dev/null | tr -d '\\r\\n' || true)"''' + t[m.end():]
    print('regex replaced')

# Force storage.json telemetry overwrite from golden (not keep local devDeviceId)
old_jq = '''                | .["telemetry.machineId"] = ($remote["telemetry.machineId"] // .["telemetry.machineId"])
                | .["telemetry.macMachineId"] = ($remote["telemetry.macMachineId"] // .["telemetry.macMachineId"])
                | .["telemetry.devDeviceId"] = ($remote["telemetry.devDeviceId"] // .["telemetry.devDeviceId"])
                | .["telemetry.sqmId"] = ($remote["telemetry.sqmId"] // .["telemetry.sqmId"])'''
new_jq = '''                | .["telemetry.machineId"] = ($remote["telemetry.machineId"] // .["telemetry.machineId"])
                | .["telemetry.macMachineId"] = ($remote["telemetry.macMachineId"] // .["telemetry.macMachineId"])
                | .["telemetry.devDeviceId"] = ($remote["telemetry.devDeviceId"] // $remote["telemetry.machineId"] // .["telemetry.devDeviceId"])
                | .["telemetry.sqmId"] = ($remote["telemetry.sqmId"] // .["telemetry.sqmId"])'''
if old_jq in t:
    t = t.replace(old_jq, new_jq, 1)
    print('OK storage jq')
else:
    print('WARN storage jq')

gm.write_bytes(t.replace('\r\n','\n').replace('\r','\n').encode())

# verify critical snippets
t = gm.read_text(encoding='utf-8')
assert 'write_cursor_profile_machineid' in t
assert "sshx 'tr -d" in t
assert 'machineid_file_mismatch' in t
assert '20260717.29' in (root/'scripts/client/mac/connect.sh').read_text(encoding='utf-8')
# show write_cursor and push and needs
for label, needle in [('write', 'write_cursor_profile_machineid()'), ('push case', "*)           rpath="), ('needs', 'machineid_file_mismatch')]:
    i = t.find(needle)
    print('---', label, '---')
    print(t[i:i+500] if i>=0 else 'MISSING')

print('OK')
