import subprocess, tempfile, os
from pathlib import Path

repo = Path(r"D:\Smart\Claude-Code-Server")
el = (repo / "scripts/client/editor-launch.ps1").read_bytes()
ver = b"20260715.18"
win_ps1 = (repo / "scripts/client/windows/connect.ps1").read_bytes()
# normalize LF for shell runners
def strip(data: bytes) -> bytes:
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

el = strip(el)
# Windows connect.ps1 for Smart - keep CRLF ok for PS; for upload as-is is fine

cred = (repo / "publish/sepidz-deploy.local.ps1").read_text(encoding="utf-8-sig")
pw = None
for line in cred.splitlines():
    if "SepidzSudoPassword" in line and "=" in line:
        pw = line.split("=", 1)[1].strip().strip("'\"")
        break

tmpdir = repo / "scripts/tmp/bundle-fix"
tmpdir.mkdir(parents=True, exist_ok=True)
(tmpdir / "editor-launch.ps1").write_bytes(el)
(tmpdir / "connect-version.txt").write_bytes(ver + b"\n")
(tmpdir / "connect.ps1.smart").write_bytes(strip(win_ps1) if False else win_ps1)

# Sepidz connect.ps1: patch IP
sep_ps1 = win_ps1.replace(b"192.168.210.240", b"192.168.250.70")
if b"192.168.250.70" not in sep_ps1:
    raise SystemExit("IP patch failed")
(tmpdir / "connect.ps1.sepidz").write_bytes(sep_ps1)

# also bump ConnectVersion already .18 in file

def scp(local, remote_target):
    r = subprocess.run(["scp", "-o", "BatchMode=yes", "-o", "ConnectTimeout=30", "-q", str(local), remote_target])
    if r.returncode != 0:
        raise SystemExit(f"scp failed {local} -> {remote_target}")

def ssh(server, cmd, timeout=60):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", f"-oConnectTimeout={timeout}", server, cmd], capture_output=True, text=True)

# ---- Sepidz with sudo password ----
print("Deploy Sepidz bundle kill-fix...")
server = "sepidz@192.168.250.70"
scp(tmpdir / "editor-launch.ps1", f"{server}:/tmp/editor-launch.ps1")
scp(tmpdir / "connect-version.txt", f"{server}:/tmp/connect-version.txt")
scp(tmpdir / "connect.ps1.sepidz", f"{server}:/tmp/connect.ps1")
pw_esc = pw.replace("'", "'\"'\"'")
runner = f"""#!/bin/bash
set -eu
echo '{pw_esc}' | sudo -S bash -c '
set -e
DEST=/usr/local/share/claude-client
cp /tmp/editor-launch.ps1 $DEST/editor-launch.ps1
cp /tmp/connect.ps1 $DEST/connect.ps1
cp /tmp/connect-version.txt $DEST/connect-version.txt
chmod 644 $DEST/editor-launch.ps1 $DEST/connect.ps1 $DEST/connect-version.txt
# nested windows/ if exists
if [ -d $DEST/windows ]; then
  cp /tmp/editor-launch.ps1 $DEST/windows/editor-launch.ps1
  cp /tmp/connect.ps1 $DEST/windows/connect.ps1
  cp /tmp/connect-version.txt $DEST/windows/connect-version.txt
fi
grep -q preserve_open_windows $DEST/editor-launch.ps1
grep -q 20260715.18 $DEST/connect-version.txt
! grep -q pre_launch_agent_or_new_window $DEST/editor-launch.ps1 || {{ echo STILL_HAS_FORCE; exit 1; }}
echo SEPIDZ_BUNDLE_OK
'
"""
(tmpdir / "run-sepidz.sh").write_bytes(runner.replace("\r\n","\n").encode())
scp(tmpdir / "run-sepidz.sh", f"{server}:/tmp/run-sepidz-bundle-fix.sh")
r = ssh(server, "chmod +x /tmp/run-sepidz-bundle-fix.sh && bash /tmp/run-sepidz-bundle-fix.sh", timeout=60)
print(r.stdout)
print(r.stderr)
if r.returncode != 0:
    raise SystemExit(f"Sepidz deploy rc={r.returncode}")

# ---- Smart: try sudo -n first, else report NEED_PASSWORD ----
print("Deploy Smart bundle kill-fix...")
server = "smart@192.168.210.240"
scp(tmpdir / "editor-launch.ps1", f"{server}:/tmp/editor-launch.ps1")
scp(tmpdir / "connect-version.txt", f"{server}:/tmp/connect-version.txt")
scp(tmpdir / "connect.ps1.smart" if (tmpdir / "connect.ps1.smart").exists() else (repo / "scripts/client/windows/connect.ps1"), f"{server}:/tmp/connect.ps1")
# rewrite smart connect.ps1 upload
scp(repo / "scripts/client/windows/connect.ps1", f"{server}:/tmp/connect.ps1")
cmd = """sudo -n bash -c 'set -e
DEST=/usr/local/share/claude-client
cp /tmp/editor-launch.ps1 $DEST/editor-launch.ps1
cp /tmp/connect.ps1 $DEST/connect.ps1
cp /tmp/connect-version.txt $DEST/connect-version.txt
chmod 644 $DEST/editor-launch.ps1 $DEST/connect.ps1 $DEST/connect-version.txt
grep -q preserve_open_windows $DEST/editor-launch.ps1
grep -q 20260715.18 $DEST/connect-version.txt
! grep -q pre_launch_agent_or_new_window $DEST/editor-launch.ps1
echo SMART_BUNDLE_OK' 2>&1 || echo SMART_NEED_SUDO"""
r = ssh(server, cmd, timeout=30)
print(r.stdout)
print(r.stderr)
print("done")
