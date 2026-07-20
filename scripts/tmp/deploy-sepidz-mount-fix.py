import subprocess
from pathlib import Path

repo = Path.cwd()
server = "sepidz@192.168.250.70"
deploy_dir = "claude-mount-deploy"

text = (repo / "publish/sepidz-deploy.local.ps1").read_text(encoding="utf-8-sig")
pw = None
for line in text.splitlines():
    if "SepidzSudoPassword" in line and "=" in line:
        pw = line.split("=", 1)[1].strip().strip("'\"")
        break
if not pw:
    raise SystemExit("no sudo password")

files = [
    ("scripts/server/claude-mount.sh", "claude-mount.sh"),
    ("scripts/server/claude-automount.sh", "claude-automount.sh"),
    ("scripts/server/claude-watchdog.sh", "claude-watchdog.sh"),
    ("scripts/server/commands/deploy-mount-fix.sh", "deploy-mount-fix.sh"),
]
subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", server, f"mkdir -p ~/{deploy_dir}"], check=True)
tmpdir = repo / "scripts/tmp"
tmpdir.mkdir(parents=True, exist_ok=True)
for src, name in files:
    p = repo / src
    if not p.exists():
        raise SystemExit(f"missing {p}")
    data = p.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    tmp = tmpdir / name
    tmp.write_bytes(data)
    subprocess.run(["scp", "-o", "BatchMode=yes", "-o", "ConnectTimeout=30", "-q", str(tmp), f"{server}:~/{deploy_dir}/{name}"], check=True)
    print(f"uploaded {name}")

pw_esc = pw.replace("'", "'\"'\"'")
remote_cmd = (
    f"chmod +x ~/{deploy_dir}/deploy-mount-fix.sh && "
    f"echo '{pw_esc}' | sudo -S bash ~/{deploy_dir}/deploy-mount-fix.sh"
)
r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=180", server, remote_cmd])
if r.returncode != 0:
    raise SystemExit(f"deploy failed rc={r.returncode}")

checks = [
    "bash -n /usr/local/lib/claude-mount && echo lib-ok",
    "grep -q _load_active_mount /usr/local/bin/claude-watchdog && echo watchdog-ok",
    "sudo -u farzadb bash -n /home/farzadb/.local/bin/claude-mount && echo farzadb-ok",
    "sudo -u farzadb /home/farzadb/.local/bin/claude-mount list 2>&1 | head -5 || true",
]
for cmd in checks:
    print(">", cmd)
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", server, cmd], check=False)
print("Sepidz mount fix complete")
