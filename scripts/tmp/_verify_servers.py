import os, re, sys
from pathlib import Path
import paramiko
ROOT=Path(r"D:\Smart\Claude-Code-Server")
EXPECTED="20260717.5"

def pw(file, name):
    p=ROOT/"publish"/file
    t=p.read_text(encoding="utf-8", errors="replace")
    m=re.search(rf"{name}\s*=\s*'([^']*)'", t)
    return m.group(1) if m else None

def check(label, host, user):
    c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, timeout=15, allow_agent=True, look_for_keys=True)
    def run(cmd):
        _,o,e=c.exec_command(cmd, timeout=30)
        return o.read().decode("utf-8","replace").strip().lstrip("\ufeff")
    ver=run("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    print(f"VER|{label}|{ver}")
    checks={
      "banner_miss": run("grep -c banner_miss_tcp_open /usr/local/share/claude-client/git-mode.ps1 || true"),
      "nc_w2": run("grep -c 'nc -w 2' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "reattach": run("grep -c 'Reattach BEFORE' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "pos_cache": run("grep -c 'Positive cache only' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "double_nc": run("grep -c 'timeout 2 nc 127.0.0.1' /usr/local/share/claude-client/git-mode.ps1 || true"),
      "syncOk": run("grep -c tunnelSyncOk /usr/local/share/claude-client/connect.ps1 || true"),
      "diag": run("grep -c tunnelEffectivelyUp /usr/local/share/claude-client/connect-diagnostic.ps1 || true"),
      "ver_in_ps1": run(f"grep -c \"ConnectVersion = '{EXPECTED}'\" /usr/local/share/claude-client/connect.ps1 || true"),
    }
    for k,v in checks.items():
        print(f"M|{label}|{k}|{v}")
    # live banner probe on server (single nc) â€” only meaningful on Smart where THIS laptop tunnel is
    if label=="Smart":
        banner=run("timeout 3 nc -w 2 127.0.0.1 21003 2>/dev/null | head -1 | tr -d '\\r'")
        print(f"PROBE|{label}|{banner}")
        sshok=run("timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/claude_laptop -p 21003 Smart@127.0.0.1 echo SSH_OK 2>/dev/null | tail -1")
        print(f"SSHOK|{label}|{sshok}")
    c.close()

check("Smart","192.168.210.240","smart")
user=None
t=(ROOT/"publish"/"sepidz-deploy.local.ps1").read_text(encoding="utf-8",errors="replace")
m=re.search(r"SepidzSshUser\s*=\s*'([^']*)'", t)
user=m.group(1) if m else "sepidz"
check("Sepidz","192.168.250.70", user)
print("PY_DONE")
