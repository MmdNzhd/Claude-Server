# -*- coding: utf-8 -*-
import pathlib, sys
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
KEY = pathlib.Path.home() / '.ssh' / 'id_ed25519'
EXPECT = '20260717.3'

def probe(tag, host, user):
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    cmd = r"""
B=/usr/local/share/claude-client
echo VER=$(tr -d '\r\n' < "$B/connect-version.txt")
echo AUTH=$(grep -c Get-CursorAuthTempRoot "$B/cursor-auth-laptop.ps1" || true)
echo SCAN=$(grep -c 'Default User' "$B/editor-launch.ps1" || true)
echo TUNNEL=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' "$B/git-mode.ps1" || true)
echo FORCE=$(grep -c pre_launch_agent_or_new_window "$B/editor-launch.ps1" || true)
echo DIAG=$(grep -c 'not found for this Windows user' "$B/connect-diagnostic.ps1" || true)
echo PRESERVE=$(grep -c preserve_open_windows "$B/editor-launch.ps1" || true)
"""
    _, o, _ = c.exec_command(cmd, timeout=30)
    out = o.read().decode().strip()
    c.close()
    d = dict(line.split('=', 1) for line in out.splitlines() if '=' in line)
    def n(k):
        return int((d.get(k, '0') or '0').split()[0] or 0)
    ver = d.get('VER', '')
    ok = (ver == EXPECT and n('AUTH') >= 1 and n('SCAN') >= 1 and n('TUNNEL') >= 1
          and n('FORCE') == 0 and n('DIAG') >= 1 and n('PRESERVE') >= 1)
    print(f'{tag}: ver={ver} auth={n("AUTH")} scan={n("SCAN")} tunnel={n("TUNNEL")} force={n("FORCE")} diag={n("DIAG")} preserve={n("PRESERVE")} => {"PASS" if ok else "FAIL"}')
    return ok

a = probe('SEPIDZ', '192.168.250.70', 'sepidz')
b = probe('SMART', '192.168.210.240', 'smart')
print('ALL_OK' if (a and b) else 'NOT_ALL_OK')
sys.exit(0 if (a and b) else 1)
