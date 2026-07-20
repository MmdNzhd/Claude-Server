# -*- coding: utf-8 -*-
import pathlib, re, sys
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
KEY = pathlib.Path.home() / ".ssh" / "id_ed25519"
EXPECT = "20260717.3"

def smart_pw():
    t = (ROOT / "publish" / "smart-deploy.local.ps1").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"SmartSudoPassword\s*=\s*'([^']*)'", t) or re.search(r'SmartSudoPassword\s*=\s*"([^"]*)"', t)
    return m.group(1) if m else None

pw = smart_pw()
if not pw:
    print("NO_PW"); sys.exit(2)
print("pw_len", len(pw))

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)

def run(cmd, timeout=60, use_pw=False):
    if not use_pw:
        _, so, se = c.exec_command(cmd, timeout=timeout)
        out, err = so.read().decode("utf-8","replace"), se.read().decode("utf-8","replace")
        return so.channel.recv_exit_status(), out, err
    stdin, so, se = c.exec_command(cmd, timeout=timeout, get_pty=True)
    stdin.write(pw + "\n"); stdin.flush()
    out, err = so.read().decode("utf-8","replace"), se.read().decode("utf-8","replace")
    return so.channel.recv_exit_status(), out, err

def markers():
    rc, out, _ = run(r"""B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1 || true)
echo scan=$(grep -c 'Default User' $B/editor-launch.ps1 || true)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1 || true)
echo force=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1 || true)
echo diag=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1 || true)
""")
    return out.strip()

print("BEFORE:", markers().replace("\n", " | "))

# ensure helper + zip ready
run("chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh ~/install-client-bundle-now.sh 2>/dev/null; sed -i 's/\\r$//' ~/claude-client-bundle-deploy/install-client-bundle.sh")
rc, out, err = run("python3 -c \"import zipfile;z=zipfile.ZipFile('/home/smart/claude-client-bundle-deploy/bundle.zip');print(z.read('connect-version.txt').decode().strip())\"")
print("zip_ver", out.strip())

rc, out, err = run("bash -lc 'sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip'", timeout=180, use_pw=True)
safe = (out + "\n" + err).replace("\ufeff","").replace(pw, "***").encode("ascii","replace").decode("ascii")
print("install_rc", rc)
print(safe[-700:])

after = markers()
print("AFTER:", after.replace("\n", " | "))
c.close()

ok = (f"version={EXPECT}" in after and ("auth=2" in after or "auth=1" in after) and ("scan=1" in after or "scan=2" in after) and "force=0" in after and ("diag=1" in after or "diag=2" in after))
print("SMART_OK" if ok else "SMART_FAIL")

# also confirm sepidz still good
c2 = paramiko.SSHClient(); c2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c2.connect("192.168.250.70", username="sepidz", key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)
_, o, _ = c2.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
print("SEPIDZ_VER", o.read().decode().strip())
c2.close()
sys.exit(0 if ok else 1)
