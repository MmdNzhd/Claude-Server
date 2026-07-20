$ErrorActionPreference='Stop'
$py = @'
import os, sys, time, zipfile, tempfile, shutil, pathlib
import paramiko

ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
DESK = pathlib.Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish"
SMART_CLIENT = DESK / "claude-code-client-20260717"
SEPID_CLIENT = DESK / "claude-code-sepidz-20260717" / "claude-code"
EXPECT = "20260717.2"
KEY = pathlib.Path(os.environ["USERPROFILE"]) / ".ssh" / "id_ed25519"

WIN = [
 "connect.bat","connect-version.txt","connect.ps1","connect-rider.bat","connect-update.ps1",
 "connect-ui.ps1","connect-diagnostic.ps1","editor-launch.ps1","git-mode.ps1","cursor-auth-laptop.ps1"
]
MAC = ["connect.sh","connect-update.sh","connect-version.txt","git-mode.sh","connect-ui.sh","editor-launch.sh","claude-mount.sh"]
SRV = [
 "scripts/server/laptop-exec.sh","scripts/server/laptop-exec-setup.sh",
 "scripts/server/claude-mount.sh","scripts/server/claude-git-setup.sh"
]
EXTRAS = [
 ("scripts/server/cursor-rules/laptop-exec.mdc","cursor-rules/laptop-exec.mdc"),
 ("scripts/server/skills/laptop-exec/SKILL.md","skills/laptop-exec/SKILL.md"),
 ("scripts/server/cursor-hooks/laptop-exec-guard.sh","cursor-hooks/laptop-exec-guard.sh"),
 ("scripts/server/cursor-hooks/hooks-user.json","cursor-hooks/hooks-user.json"),
]

def read_sepidz_pw():
    p = ROOT / "publish" / "sepidz-deploy.local.ps1"
    text = p.read_text(encoding="utf-8", errors="replace")
    import re
    m = re.search(r"SepidzSudoPassword\s*=\s*'([^']*)'", text)
    if not m:
        m = re.search(r'SepidzSudoPassword\s*=\s*"([^"]*)"', text)
    if not m:
        raise SystemExit("no SepidzSudoPassword")
    return m.group(1)

def build_zip(client_root: pathlib.Path) -> pathlib.Path:
    stage = pathlib.Path(tempfile.mkdtemp(prefix="claude-bundle-"))
    (stage/"windows").mkdir()
    (stage/"mac").mkdir()
    for n in WIN:
        shutil.copy2(client_root/"windows"/n, stage/"windows"/n)
    for n in MAC:
        shutil.copy2(client_root/"mac"/n, stage/"mac"/n)
    for rel in SRV:
        src = ROOT / rel.replace("/", "\\")
        if src.exists():
            shutil.copy2(src, stage / pathlib.Path(rel).name)
    for src_rel, dst_rel in EXTRAS:
        src = ROOT / src_rel.replace("/", "\\")
        if src.exists():
            dst = stage / dst_rel.replace("/", "\\")
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    zpath = pathlib.Path(tempfile.gettempdir()) / f"bundle-{client_root.name}.zip"
    if zpath.exists():
        zpath.unlink()
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for fp in stage.rglob("*"):
            if fp.is_file():
                z.write(fp, fp.relative_to(stage).as_posix())
    shutil.rmtree(stage, ignore_errors=True)
    return zpath

def connect(host, user):
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(hostname=host, username=user, key_filename=str(KEY), timeout=20, banner_timeout=20, auth_timeout=20, allow_agent=False, look_for_keys=False)
    return c

def remote_ver(c):
    _, stdout, _ = c.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt", timeout=30)
    return stdout.read().decode().strip()

def install_bundle(c, zip_path: pathlib.Path, sudo_password: str | None):
    install_local = ROOT / "scripts" / "server" / "commands" / "install-client-bundle.sh"
    sftp = c.open_sftp()
    try:
        try:
            sftp.mkdir("claude-client-bundle-deploy")
        except IOError:
            pass
        sftp.put(str(zip_path), "claude-client-bundle-deploy/bundle.zip")
        sftp.put(str(install_local), "claude-client-bundle-deploy/install-client-bundle.sh")
    finally:
        sftp.close()
    c.exec_command("chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh", timeout=30)
    cmd = "sudo -n bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip"
    stdin, stdout, stderr = c.exec_command(cmd, timeout=60)
    rc = stdout.channel.recv_exit_status()
    if rc != 0 and sudo_password:
        # Use sudo -S
        cmd2 = "bash -lc \"sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip\""
        stdin, stdout, stderr = c.exec_command(cmd2, timeout=180, get_pty=True)
        stdin.write(sudo_password + "\n")
        stdin.flush()
        out = stdout.read().decode(errors="replace")
        err = stderr.read().decode(errors="replace")
        rc = stdout.channel.recv_exit_status()
        print(f"sudo_install_rc={rc}")
        if out.strip():
            print(out[-500:])
        if err.strip():
            print(err[-300:])
    else:
        print(f"nopass_install_rc={rc}")
        print(stderr.read().decode(errors="replace")[-300:])
    return remote_ver(c)

def markers(c):
    cmd = r"""B=/usr/local/share/claude-client; echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1); echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1); echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1); echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)"""
    _, stdout, _ = c.exec_command(cmd, timeout=30)
    return stdout.read().decode().strip()

def deploy(label, host, user, client, pw):
    print(f"\n=== {label} {user}@{host} ===")
    verfile = (client/"windows"/"connect-version.txt").read_text().strip()
    print(f"package_ver={verfile}")
    if verfile != EXPECT:
        raise SystemExit(f"package version {verfile} != {EXPECT}")
    z = build_zip(client)
    print(f"zip={z} size={z.stat().st_size}")
    c = connect(host, user)
    try:
        before = remote_ver(c)
        print(f"before={before}")
        after = install_bundle(c, z, pw)
        print(f"after={after}")
        print(markers(c))
        if after != EXPECT:
            raise SystemExit(f"{label} version mismatch: {after}")
        print(f"OK {label}")
    finally:
        c.close()

def main():
    sepid_pw = read_sepidz_pw()
    # Sepidz first
    deploy("SEPIDZ", "192.168.250.70", "sepidz", SEPID_CLIENT, sepid_pw)
    # Smart - try without password; may fail
    smart_pw = None
    local = ROOT / "publish" / "smart-deploy.local.ps1"
    if local.exists():
        import re
        t = local.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"SmartSudoPassword\s*=\s*'([^']*)'", t) or re.search(r'SmartSudoPassword\s*=\s*"([^"]*)"', t)
        if m:
            smart_pw = m.group(1)
    try:
        deploy("SMART", "192.168.210.240", "smart", SMART_CLIENT, smart_pw)
    except Exception as e:
        print(f"SMART_DEPLOY_ERROR: {e}")
        # Leave zip ready on server via note
        sys.exit(2)

if __name__ == "__main__":
    main()
'@
$pyPath = Join-Path $env:TEMP 'paramiko-deploy-both.py'
Set-Content -Path $pyPath -Value $py -Encoding UTF8
python $pyPath
Write-Host "python_exit=$LASTEXITCODE"
