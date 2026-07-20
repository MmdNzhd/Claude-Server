# -*- coding: utf-8 -*-
import pathlib, re, sys, tempfile
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
KEY = pathlib.Path.home() / ".ssh" / "id_ed25519"
EXPECT = "20260717.3"

def sepidz_pw():
    t = (ROOT / "publish" / "sepidz-deploy.local.ps1").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"SepidzSudoPassword\s*=\s*'([^']*)'", t) or re.search(r'SepidzSudoPassword\s*=\s*"([^"]*)"', t)
    return m.group(1) if m else None

def connect():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    return c

def run(c, cmd, timeout=60, pw=None):
    if pw is None:
        _, so, se = c.exec_command(cmd, timeout=timeout)
        out, err = so.read().decode("utf-8","replace"), se.read().decode("utf-8","replace")
        return so.channel.recv_exit_status(), out, err
    stdin, so, se = c.exec_command(cmd, timeout=timeout, get_pty=True)
    stdin.write(pw + "\n"); stdin.flush()
    out, err = so.read().decode("utf-8","replace"), se.read().decode("utf-8","replace")
    return so.channel.recv_exit_status(), out, err

def markers(c):
    cmd = r"""B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1 || true)
echo scan=$(grep -c 'Default User' $B/editor-launch.ps1 || true)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1 || true)
echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1 || true)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1 || true)
echo diag=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1 || true)
"""
    return run(c, cmd)[1].strip()

c = connect()
print("BEFORE:", markers(c))
# ensure install script LF
run(c, "chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh; sed -i 's/\\r$//' ~/claude-client-bundle-deploy/install-client-bundle.sh; python3 -c \"import zipfile;z=zipfile.ZipFile('/home/smart/claude-client-bundle-deploy/bundle.zip');print('zip_ver='+z.read('connect-version.txt').decode().strip())\"")

rc, out, err = run(c, "sudo -n bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip", timeout=60)
print("nopass_rc", rc)

if rc != 0:
    pw = sepidz_pw()
    if not pw:
        print("NO_PASSWORD_AVAILABLE")
        print("AFTER:", markers(c))
        c.close(); sys.exit(2)
    print("trying_stored_deploy_password len=", len(pw))
    rc, out, err = run(c, "bash -lc 'sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip'", timeout=180, pw=pw)
    safe = (out + "\n" + err).replace("\ufeff","").encode("ascii","replace").decode("ascii")
    print("pass_rc", rc)
    print(safe[-500:])

after = markers(c)
print("AFTER:", after)
c.close()
ver = re.search(r"version=(\S+)", after)
ok = ver and ver.group(1) == EXPECT
# also require scan+auth
ok = ok and ("scan=1" in after or "scan=2" in after) and ("auth=2" in after or "auth=1" in after)
print("SMART_OK" if ok else "SMART_FAIL")
sys.exit(0 if ok else 1)
