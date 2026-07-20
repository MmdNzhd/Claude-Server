import subprocess
from pathlib import Path
repo = Path.cwd()
server = "sepidz@192.168.250.70"
text = (repo / "publish/sepidz-deploy.local.ps1").read_text(encoding="utf-8-sig")
pw = next(line.split("=",1)[1].strip().strip("'\"") for line in text.splitlines() if "SepidzSudoPassword" in line and "=" in line)
data = (repo / "scripts/tmp/verify-sepidz-on-server.sh").read_bytes().replace(b"\r\n", b"\n")
(repo / "scripts/tmp/verify-sepidz-on-server.sh").write_bytes(data)
subprocess.run(["scp", "-o", "BatchMode=yes", "-o", "ConnectTimeout=30", "-q", str(repo / "scripts/tmp/verify-sepidz-on-server.sh"), f"{server}:~/verify-sepidz-on-server.sh"], check=True)
pw_esc = pw.replace("'", "'\"'\"'")
cmd = f"chmod +x ~/verify-sepidz-on-server.sh && echo '{pw_esc}' | sudo -S bash ~/verify-sepidz-on-server.sh"
subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=120", server, cmd], check=False)
