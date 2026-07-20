# -*- coding: utf-8 -*-
import os, sys, re, shutil, zipfile, tempfile, pathlib, time, subprocess
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
DESK = pathlib.Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish"
KEY = pathlib.Path(os.environ["USERPROFILE"]) / ".ssh" / "id_ed25519"
EXPECT = "20260717.3"
INSTALL_SRC = ROOT / "scripts" / "server" / "commands" / "install-client-bundle.sh"

WIN = ['connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1']
MAC = ['connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh']
SRV = ['laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json']

def read_pw(fname, varname):
    p = ROOT / "publish" / fname
    if not p.exists(): return None
    t = p.read_text(encoding='utf-8', errors='replace')
    m = re.search(rf"{varname}\s*=\s*'([^']*)'", t) or re.search(rf'{varname}\s*=\s*"([^"]*)"', t)
    return m.group(1) if m else None

def build_zip(client: pathlib.Path, label: str) -> pathlib.Path:
    stage = pathlib.Path(tempfile.mkdtemp(prefix=f"stage-{label}-"))
    try:
        for n in WIN:
            shutil.copy2(client / "windows" / n, stage / n)
        (stage / "mac").mkdir()
        for n in MAC:
            shutil.copy2(client / "mac" / n, stage / "mac" / n)
        for rel in SRV:
            src = ROOT / "scripts" / "server" / pathlib.Path(*rel.split("/"))
            dst = stage / "server" / pathlib.Path(*rel.split("/"))
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        zpath = pathlib.Path(tempfile.gettempdir()) / f"bundle-{label}-{EXPECT}.zip"
        if zpath.exists(): zpath.unlink()
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            for fp in stage.rglob("*"):
                if fp.is_file():
                    z.write(fp, fp.relative_to(stage).as_posix())
        with zipfile.ZipFile(zpath) as z:
            names = z.namelist()
            assert "connect.ps1" in names
            assert "editor-launch.ps1" in names
            el = z.read("editor-launch.ps1").decode("utf-8", "replace")
            assert "Default User" in el
            print(f"ZIP={zpath} entries={len(names)} ver={z.read('connect-version.txt').decode().strip()}")
        return zpath
    finally:
        shutil.rmtree(stage, ignore_errors=True)

def connect(host, user):
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=25, banner_timeout=25, auth_timeout=25, allow_agent=False, look_for_keys=False)
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
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1)
echo scan_users=$(grep -c 'Default User' $B/editor-launch.ps1)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1)
echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)
echo diag_fix=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1)
"""
    return run(c, cmd)[1].strip()

def upload_and_install(label, host, user, client, pw):
    print(f"\n=== {label} ===", flush=True)
    z = build_zip(client, label.lower())
    install_tmp = pathlib.Path(tempfile.gettempdir()) / f"install-{label}.sh"
    install_tmp.write_bytes(INSTALL_SRC.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
    c = connect(host, user)
    try:
        print("before:", run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")[1].strip(), flush=True)
        sftp = c.open_sftp()
        try:
            try: sftp.mkdir("claude-client-bundle-deploy")
            except IOError: pass
            sftp.put(str(z), "claude-client-bundle-deploy/bundle.zip")
            sftp.put(str(install_tmp), "claude-client-bundle-deploy/install-client-bundle.sh")
        finally:
            sftp.close()
        run(c, "chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh; sed -i 's/\\r$//' ~/claude-client-bundle-deploy/install-client-bundle.sh")
        if pw:
            rc, out, err = run(c, "bash -lc 'sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip'", timeout=180, pw=pw)
        else:
            rc, out, err = run(c, "sudo -n bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip", timeout=60)
        safe = (out+"\n"+err).replace("\ufeff","").encode("ascii","replace").decode("ascii")
        print("install_rc", rc, flush=True)
        print(safe[-700:], flush=True)
        print(markers(c), flush=True)
        ver = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")[1].strip()
        return ver == EXPECT
    finally:
        c.close()

def poll_smart(expect_sec=180):
    title = "SMART sudo - enter password for v20260717.3"
    ssh = 'ssh -t -o ConnectTimeout=20 smart@192.168.210.240 "sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip; echo DONE_EXIT=$?; exec bash"'
    subprocess.Popen(["cmd.exe", "/c", f"start \"{title}\" cmd /k \"title {title} && {ssh}\""])
    print("Opened Smart sudo window; polling...", flush=True)
    deadline = time.time() + expect_sec
    while time.time() < deadline:
        try:
            c = connect("192.168.210.240", "smart")
            ver = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")[1].strip()
            print("poll", ver, flush=True)
            if ver == EXPECT:
                print(markers(c), flush=True); c.close(); return True
            c.close()
        except Exception as e:
            print("poll_err", e, flush=True)
        time.sleep(5)
    return False

def main():
    sepid_pw = read_pw("sepidz-deploy.local.ps1", "SepidzSudoPassword")
    smart_pw = read_pw("smart-deploy.local.ps1", "SmartSudoPassword")
    ok_s = upload_and_install("SEPIDZ", "192.168.250.70", "sepidz", DESK/"claude-code-sepidz-20260717"/"claude-code", sepid_pw)
    if not ok_s: raise SystemExit("SEPIDZ failed")
    print("OK SEPIDZ", flush=True)
    ok_m = upload_and_install("SMART", "192.168.210.240", "smart", DESK/"claude-code-client-20260717", smart_pw)
    if ok_m:
        print("OK SMART", flush=True); return
    print("SMART needs interactive sudo", flush=True)
    if poll_smart():
        print("OK SMART", flush=True); return
    raise SystemExit(2)

if __name__ == "__main__":
    main()
