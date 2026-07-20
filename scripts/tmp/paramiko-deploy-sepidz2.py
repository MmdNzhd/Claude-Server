# -*- coding: utf-8 -*-
import os, sys, re, zipfile, tempfile, shutil, pathlib
import paramiko

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
CLIENT = pathlib.Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish" / "claude-code-sepidz-20260717" / "claude-code"
EXPECT = "20260717.2"
KEY = pathlib.Path(os.environ["USERPROFILE"]) / ".ssh" / "id_ed25519"

WIN = ["connect.bat","connect-version.txt","connect.ps1","connect-rider.bat","connect-update.ps1","connect-ui.ps1","connect-diagnostic.ps1","editor-launch.ps1","git-mode.ps1","cursor-auth-laptop.ps1"]
MAC = ["connect.sh","connect-update.sh","connect-version.txt","git-mode.sh","connect-ui.sh","editor-launch.sh","claude-mount.sh"]

def read_pw():
    text = (ROOT/"publish"/"sepidz-deploy.local.ps1").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"SepidzSudoPassword\s*=\s*'([^']*)'", text) or re.search(r'SepidzSudoPassword\s*=\s*"([^"]*)"', text)
    if not m: raise SystemExit("no pw")
    return m.group(1)

def build_zip():
    stage = pathlib.Path(tempfile.mkdtemp(prefix="cb-"))
    (stage/"windows").mkdir(); (stage/"mac").mkdir()
    for n in WIN: shutil.copy2(CLIENT/"windows"/n, stage/"windows"/n)
    for n in MAC: shutil.copy2(CLIENT/"mac"/n, stage/"mac"/n)
    for rel in ["scripts/server/laptop-exec.sh","scripts/server/laptop-exec-setup.sh","scripts/server/claude-mount.sh","scripts/server/claude-git-setup.sh"]:
        src = ROOT/rel.replace("/","\\")
        if src.exists(): shutil.copy2(src, stage/pathlib.Path(rel).name)
    for src_rel, dst_rel in [
        ("scripts/server/cursor-rules/laptop-exec.mdc","cursor-rules/laptop-exec.mdc"),
        ("scripts/server/skills/laptop-exec/SKILL.md","skills/laptop-exec/SKILL.md"),
        ("scripts/server/cursor-hooks/laptop-exec-guard.sh","cursor-hooks/laptop-exec-guard.sh"),
        ("scripts/server/cursor-hooks/hooks-user.json","cursor-hooks/hooks-user.json"),
    ]:
        src = ROOT/src_rel.replace("/","\\")
        if src.exists():
            dst = stage/dst_rel.replace("/","\\"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
    zpath = pathlib.Path(tempfile.gettempdir())/"bundle-sepidz-20260717.2.zip"
    if zpath.exists(): zpath.unlink()
    with zipfile.ZipFile(zpath,"w",zipfile.ZIP_DEFLATED) as z:
        for fp in stage.rglob("*"):
            if fp.is_file(): z.write(fp, fp.relative_to(stage).as_posix())
    shutil.rmtree(stage, ignore_errors=True)
    return zpath

def run(c, cmd, timeout=60, sudo_pw=None):
    if sudo_pw is None:
        stdin, stdout, stderr = c.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode("utf-8","replace")
        err = stderr.read().decode("utf-8","replace")
        rc = stdout.channel.recv_exit_status()
        return rc, out, err
    # pty + sudo -S
    stdin, stdout, stderr = c.exec_command(cmd, timeout=timeout, get_pty=True)
    stdin.write(sudo_pw + "\n")
    stdin.flush()
    out = stdout.read().decode("utf-8","replace")
    err = stderr.read().decode("utf-8","replace")
    rc = stdout.channel.recv_exit_status()
    return rc, out, err

def main():
    pw = read_pw()
    print("pw_len", len(pw))
    z = build_zip()
    print("zip", z, z.stat().st_size)
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect("192.168.250.70", username="sepidz", key_filename=str(KEY), timeout=20, banner_timeout=20, auth_timeout=20, allow_agent=False, look_for_keys=False)
    rc, out, err = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    print("before", out.strip())

    sftp = c.open_sftp()
    try:
        try: sftp.mkdir("claude-client-bundle-deploy")
        except IOError: pass
        sftp.put(str(z), "claude-client-bundle-deploy/bundle.zip")
        sftp.put(str(ROOT/"scripts/server/commands/install-client-bundle.sh"), "claude-client-bundle-deploy/install-client-bundle.sh")
    finally:
        sftp.close()
    run(c, "chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh")

    # test sudo password first
    rc, out, err = run(c, "bash -lc 'sudo -S -v'", timeout=30, sudo_pw=pw)
    print("sudo_-v_rc", rc)
    print("sudo_-v_out", repr(out[-200:]))
    print("sudo_-v_err", repr(err[-200:]))
    if rc != 0:
        # try without -v, whoami
        rc, out, err = run(c, "bash -lc 'sudo -S whoami'", timeout=30, sudo_pw=pw)
        print("sudo_whoami_rc", rc, "out", repr(out[-100:]), "err", repr(err[-100:]))

    rc, out, err = run(c, "bash -lc 'sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip'", timeout=180, sudo_pw=pw)
    print("install_rc", rc)
    # sanitize BOM
    safe = (out + "\n" + err).replace("\ufeff","").encode("ascii","replace").decode("ascii")
    print("install_out_tail:\n", safe[-800:])

    rc, out, err = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    print("after", out.strip())
    rc, out, err = run(c, r"B=/usr/local/share/claude-client; echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1); echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1); echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)")
    print(out.strip())
    c.close()
    if out.strip().split()[0] if False else True:
        pass
    ver = open if False else None
    # exit code based on version
    # re-read
    c2 = paramiko.SSHClient(); c2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c2.connect("192.168.250.70", username="sepidz", key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    _, stdout, _ = c2.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    v = stdout.read().decode().strip(); c2.close()
    print("FINAL", v)
    sys.exit(0 if v == EXPECT else 1)

if __name__ == "__main__":
    main()
