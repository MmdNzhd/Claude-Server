#!/usr/bin/env python3
from __future__ import annotations
import os, re, sys, tempfile, zipfile, shutil
from pathlib import Path
import paramiko

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

def read_local_pw(path: Path, name: str):
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
    lines = [n for n in WIN_FILES] + [f"mac/{n}" for n in MAC_FILES]
    (stage / "manifest.txt").write_text("\n".join(sorted(lines)) + "\n", encoding="utf-8")

def zip_stage(stage: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in stage.rglob("*"):
            if f.is_file():
                z.write(f, f.relative_to(stage).as_posix())

def ssh_exec(client, cmd, timeout=180):
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    return code, out, err

def safe_print(s: str) -> None:
    sys.stdout.buffer.write((s + "\n").encode("utf-8", "replace"))
    sys.stdout.flush()

def verify(client, label: str) -> None:
    _, out, _ = ssh_exec(client, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    remote_ver = out.strip().lstrip("\ufeff")
    safe_print(f"{label} remote_ver=[{remote_ver}]")
    if remote_ver != EXPECTED:
        raise SystemExit(f"{label} version mismatch: {remote_ver}")
    _, out, _ = ssh_exec(
        client,
        "grep -c banner_miss_tcp_open /usr/local/share/claude-client/git-mode.ps1; "
        "grep -c 'nc -w 2' /usr/local/share/claude-client/git-mode.ps1; "
        "grep -c tunnelSyncOk /usr/local/share/claude-client/connect.ps1; "
        "grep -c tunnelEffectivelyUp /usr/local/share/claude-client/connect-diagnostic.ps1",
    )
    parts = [x.strip() for x in out.splitlines() if x.strip()]
    safe_print(f"{label} markers banner,nc,sync,diag={parts}")
    if any(p == "0" for p in parts):
        raise SystemExit(f"{label} marker missing: {parts}")

def deploy(label, host, user, password, client_root: Path, verify_only=False):
    safe_print(f"=== {label} {user}@{host} ===")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username=user, timeout=20, allow_agent=True, look_for_keys=True)
    if verify_only:
        verify(client, label)
        client.close()
        return
    ver = (client_root / "windows" / "connect-version.txt").read_text(encoding="utf-8").strip().lstrip("\ufeff")
    if ver != EXPECTED:
        raise SystemExit(f"{label} pack version {ver} != {EXPECTED}")
    stage = Path(tempfile.mkdtemp(prefix=f"bundle-{label.lower()}-"))
    zpath = Path(tempfile.gettempdir()) / f"claude-client-bundle-{label.lower()}-paramiko.zip"
    try:
        build_stage(client_root, stage)
        zip_stage(stage, zpath)
        install_local = ROOT / "scripts" / "server" / "commands" / "install-client-bundle.sh"
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
        if not password:
            raise SystemExit(f"{label}: no sudo password")
        esc = password.replace("'", "'\\''")
        cmd = f"bash -lc \"echo '{esc}' | sudo -S bash ~/{remote_dir}/install-client-bundle.sh ~/{remote_dir}/bundle.zip\""
        code, out, err = ssh_exec(client, cmd, timeout=180)
        safe_print(f"install_exit={code}")
        if "Done." in out or "Done." in err or f"v{EXPECTED}" in out or f"v{EXPECTED}" in err:
            safe_print("install_output_has_Done")
        verify(client, label)
        safe_print(f"OK {label}")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
        if zpath.exists():
            zpath.unlink()
        client.close()

def main():
    smart_pw = read_local_pw(ROOT / "publish" / "smart-deploy.local.ps1", "SmartSudoPassword")
    sepid_pw = read_local_pw(ROOT / "publish" / "sepidz-deploy.local.ps1", "SepidzSudoPassword")
    sepid_user = read_local_pw(ROOT / "publish" / "sepidz-deploy.local.ps1", "SepidzSshUser") or "sepidz"
    # Smart may already be installed from prior run — verify first, redeploy if needed
    try:
        deploy("Smart", "192.168.210.240", "smart", smart_pw,
               PUBLISH / "claude-code-client-20260717", verify_only=True)
        safe_print("Smart already OK")
    except SystemExit as e:
        safe_print(f"Smart verify failed ({e}); redeploying")
        deploy("Smart", "192.168.210.240", "smart", smart_pw,
               PUBLISH / "claude-code-client-20260717")
    deploy("Sepidz", "192.168.250.70", sepid_user, sepid_pw,
           PUBLISH / "claude-code-sepidz-20260717" / "claude-code")
    safe_print("ALL_DEPLOY_OK")

if __name__ == "__main__":
    main()
