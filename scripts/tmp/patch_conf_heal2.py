from pathlib import Path
import re

ps = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1")
pt = ps.read_text(encoding="utf-8")
if "claude-self-heal --quiet" in pt and "PUSH_CONF" in pt:
    # check if already after Push-ServerConnectConf
    idx = pt.find("function Push-ServerConnectConf")
    chunk = pt[idx:idx+800]
    print("PS CHUNK:\n", chunk)
    if "claude-self-heal" in chunk:
        print("PS already has heal in Push-ServerConnectConf")
    else:
        # insert before closing brace of function - after SshX conf line
        needle = "chmod 600 ~/.claude-connect.conf || true\" 2>$null | Out-Null"
        pos = pt.find(needle, idx)
        if pos < 0:
            raise SystemExit('ps needle missing')
        insert_at = pos + len(needle)
        insert = "\r\n    # Win+Mac: server-side self-heal after every conf push\r\n    SshX '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' 2>$null | Out-Null"
        pt = pt[:insert_at] + insert + pt[insert_at:]
        ps.write_text(pt, encoding="utf-8", newline="\r\n")
        print("PS patched")
else:
    idx = pt.find("function Push-ServerConnectConf")
    chunk = pt[idx:idx+800]
    print("PS CHUNK:\n", chunk)
    needle = "chmod 600 ~/.claude-connect.conf || true\" 2>$null | Out-Null"
    pos = pt.find(needle, idx)
    if pos < 0:
        raise SystemExit('ps needle missing')
    insert_at = pos + len(needle)
    insert = "\r\n    # Win+Mac: server-side self-heal after every conf push\r\n    SshX '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' 2>$null | Out-Null"
    pt = pt[:insert_at] + insert + pt[insert_at:]
    ps.write_text(pt, encoding="utf-8", newline="\r\n")
    print("PS patched")

sh = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh")
st = sh.read_text(encoding="utf-8")
idx = st.find("push_server_connect_conf()")
chunk = st[idx:idx+500]
print("SH CHUNK:\n", chunk)
if "claude-self-heal" in chunk:
    print("SH already has heal")
else:
    needle = 'chmod 600 \\$HOME/.claude-connect.conf" 2>/dev/null || true'
    # actual file has \$HOME in source as $HOME after read... 
    needle2 = "chmod 600 \\$HOME/.claude-connect.conf"
    # try simpler
    m = re.search(r"chmod 600 \\\$HOME/\.claude-connect\.conf[^\n]*", st[idx:idx+400])
    if not m:
        m = re.search(r"chmod 600 \$HOME/\.claude-connect\.conf[^\n]*", st[idx:idx+400])
    if not m:
        raise SystemExit('sh chmod line missing')
    abs_pos = idx + m.end()
    insert = "\n    # Win+Mac: server-side self-heal after every conf push\n    sshx '/usr/local/bin/claude-self-heal --quiet 2>/dev/null || $HOME/.local/bin/claude-self-heal --quiet 2>/dev/null || true' >/dev/null 2>&1 || true"
    st = st[:abs_pos] + insert + st[abs_pos:]
    sh.write_text(st, encoding="utf-8", newline="\n")
    print("SH patched")

# publish
pub = Path(r"D:\Smart\Claude-Code-Server\publish\publish.ps1")
pt = pub.read_text(encoding="utf-8")
if "claude-self-heal.sh" in pt:
    print("publish already")
else:
    pt2 = pt.replace(
        'Dst = "mac\\claude-mount.sh";       PatchIp = $false }',
        'Dst = "mac\\claude-mount.sh";       PatchIp = $false }\r\n'
        '    @{ Src = "scripts\\server\\claude-self-heal.sh";       Dst = "mac\\claude-self-heal.sh";   PatchIp = $false }\r\n'
        '    @{ Src = "scripts\\server\\claude-automount.sh";       Dst = "mac\\claude-automount.sh";   PatchIp = $false }\r\n'
        '    @{ Src = "scripts\\server\\claude-self-heal.sh";       Dst = "windows\\claude-self-heal.sh"; PatchIp = $false }\r\n'
        '    @{ Src = "scripts\\server\\claude-automount.sh";       Dst = "windows\\claude-automount.sh"; PatchIp = $false }',
        1,
    )
    if pt2 == pt:
        pt2 = pt.replace(
            'Dst = "mac\\claude-mount.sh";       PatchIp = $false }',
            'Dst = "mac\\claude-mount.sh";       PatchIp = $false }\n'
            '    @{ Src = "scripts\\server\\claude-self-heal.sh";       Dst = "mac\\claude-self-heal.sh";   PatchIp = $false }\n'
            '    @{ Src = "scripts\\server\\claude-automount.sh";       Dst = "mac\\claude-automount.sh";   PatchIp = $false }\n'
            '    @{ Src = "scripts\\server\\claude-self-heal.sh";       Dst = "windows\\claude-self-heal.sh"; PatchIp = $false }\n'
            '    @{ Src = "scripts\\server\\claude-automount.sh";       Dst = "windows\\claude-automount.sh"; PatchIp = $false }',
            1,
        )
    if pt2 == pt:
        raise SystemExit('publish replace failed')
    pub.write_text(pt2, encoding="utf-8", newline="\r\n")
    print("publish patched")

print("ALL_OK")
