#!/usr/bin/env python3
"""Deploy client auto-update bundles via paramiko (avoids hung OpenSSH sudo -n)."""
from __future__ import annotations
import os, re, sys, tempfile, zipfile, shutil
from pathlib import Path

try:
    import paramiko
except ImportError:
    sys.exit("paramiko missing")

ROOT = Path(r"D:\Smart\Claude-Code-Server")
PUBLISH = Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish"
EXPECTED = "20260717.5"

WIN_FILES = [
    "connect.bat", "connect-version.txt", "connect-update.ps1", "connect.ps1",
    "connect-rider.bat", "editor-launch.ps1", "git-mode.ps1", "cursor-auth-laptop.ps1",
    "connect-ui.ps1", "connect-diagnostic.ps1",
]
MAC_FILES = [
    "connect.sh", "connect-update.sh", "connect-version.txt", "git-mode.sh",
    "connect-ui.sh", "editor-launch.sh", "claude-mount.sh",
]
SERVER_RELS = [
    # from scripts/server/ — mirrored under server/ in stage; WinBundle puts flat win files
]

def read_local_pw(path: Path, name: str) -> str | None:
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(rf"{name}\s*=\s*'([^']*)'", text)
    if m:
        return m.group(1)
    m = re.search(rf'{name}\s*=\s*"([^"]*)"', text)
    return m.group(1) if m else None

def build_stage(client_root: Path, stage: Path) -> None:
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    (stage / "mac").mkdir()
    (stage / "server").mkdir()
    for name in WIN_FILES:
        src = client_root / "windows" / name
        if not src.exists():
            raise SystemExit(f"missing {src}")
        shutil.copy2(src, stage / name)
    for name in MAC_FILES:
        src = client_root / "mac" / name
        if not src.exists():
            raise SystemExit(f"missing {src}")
        shutil.copy2(src, stage / "mac" / name)
    # optional server snippets used by install script
    for rel in [
        "commands/install-client-bundle.sh",
    ]:
        pass
    # manifest
    lines = []
    for name in WIN_FILES:
        if (stage / name).exists():
            lines.append(name)
    for name in MAC_FILES:
        if (stage / "mac" / name).exists():
            lines.append(f"mac/{name}")
    (stage / "manifest.txt").write_text("\n".join(sorted(lines)) + "\n", encoding="utf-8")

def zip_stage(stage: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in stage.rglob("*"):
            if f.is_file():
                z.write(f, f.relative_to(stage).as_posix())

def ssh_exec(client: paramiko.SSHClient, cmd: str, timeout: int = 120) -> tuple[int, str, str]:
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    return code, out, err

def deploy(label: str, host: str, user: str, password: str | None, client_root: Path) -> None:
    print(f"=== {label} {user}@{host} ===")
    ver = (client_root / "windows" / "connect-version.txt").read_text().strip()
    if ver != EXPECTED:
        raise SystemExit(f"{label} pack version {ver} != {EXPECTED}")
    stage = Path(tempfile.mkdtemp(prefix=f"bundle-{label.lower()}-"))
    zpath = Path(tempfile.gettempdir()) / f"claude-client-bundle-{label.lower()}-paramiko.zip"
    try:
        build_stage(client_root, stage)
        zip_stage(stage, zpath)
        install_local = ROOT / "scripts" / "server" / "commands" / "install-client-bundle.sh"
        if not install_local.exists():
            raise SystemExit(f"missing {install_local}")

        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        # Prefer key auth (BatchMode equivalent)
        client.connect(host, username=user, timeout=20, allow_agent=True, look_for_keys=True)
        sftp = client.open_sftp()
        remote_dir = "claude-client-bundle-deploy"
        try:
            sftp.mkdir(remote_dir)
        except IOError:
            pass
        sftp.put(str(zpath), f"{remote_dir}/bundle.zip")
        sftp.put(str(install_local), f"{remote_dir}/install-client-bundle.sh")
        sftp.close()

        ssh_exec(client, f"chmod +x ~/{remote_dir}/install-client-bundle.sh")
        if password:
            # sudo -S
            esc = password.replace("'", "'\\''")
            cmd = f"bash -lc \"echo '{esc}' | sudo -S bash ~/{remote_dir}/install-client-bundle.sh ~/{remote_dir}/bundle.zip\""
        else:
            cmd = f"sudo -n bash ~/{remote_dir}/install-client-bundle.sh ~/{remote_dir}/bundle.zip"
        code, out, err = ssh_exec(client, cmd, timeout=180)
        print(f"install exit={code}")
        if out.strip():
            print(out.strip()[-500:])
        if code != 0 and err.strip():
            print("stderr:", err.strip()[-500:])

        code2, out2, _ = ssh_exec(client, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
        remote_ver = out2.strip()
        print(f"remote_ver=[{remote_ver}]")
        if remote_ver != EXPECTED:
            raise SystemExit(f"{label} version mismatch: got {remote_ver}")
        code3, out3, _ = ssh_exec(
            client,
            "grep -c banner_miss_tcp_open /usr/local/share/claude-client/git-mode.ps1; "
            "grep -c tunnelSyncOk /usr/local/share/claude-client/connect.ps1; "
            "grep -c tunnelEffectivelyUp /usr/local/share/claude-client/connect-diagnostic.ps1",
        )
        print(f"markers={out3.strip().split()}")
        client.close()
        print(f"OK {label}")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
        if zpath.exists():
            zpath.unlink()

def main() -> None:
    smart_pw = read_local_pw(ROOT / "publish" / "smart-deploy.local.ps1", "SmartSudoPassword")
    sepid_pw = read_local_pw(ROOT / "publish" / "sepidz-deploy.local.ps1", "SepidzSudoPassword")
    sepid_user = read_local_pw(ROOT / "publish" / "sepidz-deploy.local.ps1", "SepidzSshUser") or "sepidz"
    deploy("Smart", "192.168.210.240", "smart", smart_pw, PUBLISH / "claude-code-client-20260717")
    deploy("Sepidz", "192.168.250.70", sepid_user, sepid_pw, PUBLISH / "claude-code-sepidz-20260717" / "claude-code")
    print("ALL_DEPLOY_OK")

if __name__ == "__main__":
    main()
