# -*- coding: utf-8 -*-
import os, sys, pathlib
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
KEY = pathlib.Path(os.environ["USERPROFILE"]) / ".ssh" / "id_ed25519"
DESK = pathlib.Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish"

def probe(label, host, user):
    print(f"\n=== {label} {user}@{host} ===")
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    cmd = r"""
B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1)
echo remove_safe=$(grep -c Remove-CursorAuthTempDir $B/cursor-auth-laptop.ps1)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1)
echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)
echo killSkip=$(grep -c LAUNCH_KILL_SKIP $B/editor-launch.ps1)
echo zip_ready=$(python3 -c "import zipfile;z=zipfile.ZipFile('/home/'"$USER"'/claude-client-bundle-deploy/bundle.zip');print(z.read('connect-version.txt').decode().strip() if 'connect-version.txt' in z.namelist() else 'NO')" 2>/dev/null || echo none)
"""
    _, stdout, _ = c.exec_command(cmd, timeout=30)
    print(stdout.read().decode().strip())
    c.close()

probe("SEPIDZ", "192.168.250.70", "sepidz")
probe("SMART", "192.168.210.240", "smart")

print("\n=== DESKTOP PACKS ===")
for name in ["claude-code-client-20260717", "claude-code-sepidz-20260717"]:
    p = DESK/name
    if name.startswith("claude-code-sepidz"):
        vf = p/"claude-code"/"windows"/"connect-version.txt"
        auth = p/"claude-code"/"windows"/"cursor-auth-laptop.ps1"
    else:
        vf = p/"windows"/"connect-version.txt"
        auth = p/"windows"/"cursor-auth-laptop.ps1"
    print(name, "ver=", vf.read_text().strip() if vf.exists() else "MISSING",
          "auth_fix=", ("Get-CursorAuthTempRoot" in auth.read_text(encoding='utf-8', errors='replace')) if auth.exists() else False)
print("zips:", [x.name for x in DESK.glob("*.zip") if "20260717" in x.name])
