# -*- coding: utf-8 -*-
import pathlib, paramiko, sys
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
python3 - <<'P2'
import zipfile, os
p=f"/home/{os.environ['USER']}/claude-client-bundle-deploy/bundle.zip"
try:
  z=zipfile.ZipFile(p); print('PENDING_ZIP='+z.read('connect-version.txt').decode().strip())
except Exception as e:
  print('PENDING_ZIP=NONE')
P2
"""
    _, o, _ = c.exec_command(cmd, timeout=40)
    out = o.read().decode().strip()
    c.close()
    d = {}
    for line in out.splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            d[k] = v.strip()
    ver = d.get('VER', '')
    auth = int((d.get('AUTH') or '0').split()[0] or 0)
    scan = int((d.get('SCAN') or '0').split()[0] or 0)
    tunnel = int((d.get('TUNNEL') or '0').split()[0] or 0)
    force = int((d.get('FORCE') or '0').split()[0] or 0)
    diag = int((d.get('DIAG') or '0').split()[0] or 0)
    pending = d.get('PENDING_ZIP', 'NONE')
    ok = (ver == EXPECT and auth >= 1 and scan >= 1 and tunnel >= 1 and force == 0 and diag >= 1)
    print(f'{tag}_VER={ver}')
    print(f'{tag}_AUTH={auth}')
    print(f'{tag}_SCAN={scan}')
    print(f'{tag}_TUNNEL={tunnel}')
    print(f'{tag}_FORCE={force}')
    print(f'{tag}_DIAG={diag}')
    print(f'{tag}_PENDING_ZIP={pending}')
    print(f'{tag}_OK={int(ok)}')

print(f'EXPECT={EXPECT}')
probe('SEPIDZ', '192.168.250.70', 'sepidz')
probe('SMART', '192.168.210.240', 'smart')
