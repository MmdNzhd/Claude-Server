# -*- coding: utf-8 -*-
import pathlib, re, sys, time
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
KEY = pathlib.Path.home() / ".ssh" / "id_ed25519"
t = (ROOT / "publish" / "sepidz-deploy.local.ps1").read_text(encoding="utf-8", errors="replace")
m = re.search(r"SepidzSudoPassword\s*=\s*'([^']*)'", t) or re.search(r'SepidzSudoPassword\s*=\s*"([^"]*)"', t)
pw = m.group(1) if m else None
print("pw_present", bool(pw), "len", len(pw) if pw else 0)
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)

def sudo_whoami(password, limit=12):
    chan = c.get_transport().open_session()
    chan.get_pty()
    chan.settimeout(limit)
    chan.exec_command("bash -lc 'sudo -S -p PROMPT whoami'")
    time.sleep(0.4)
    try:
        if chan.recv_ready():
            chan.recv(2048)
    except Exception:
        pass
    chan.send((password or "") + "\n")
    deadline = time.time() + limit
    buf = b""
    while time.time() < deadline:
        try:
            if chan.recv_ready():
                buf += chan.recv(4096)
        except Exception:
            break
        if chan.exit_status_ready():
            break
        time.sleep(0.2)
    rc = chan.recv_exit_status() if chan.exit_status_ready() else -1
    try:
        while chan.recv_ready():
            buf += chan.recv(4096)
    except Exception:
        pass
    chan.close()
    return rc, buf.decode("utf-8", "replace")

if pw:
    rc, out = sudo_whoami(pw)
    print("whoami_rc", rc)
    print("whoami_out", out.replace(pw, "***").encode("ascii","replace").decode("ascii")[-200:])
    if rc == 0 and "root" in out:
        print("PASSWORD_WORKS_FOR_SMART")
        chan = c.get_transport().open_session()
        chan.get_pty(); chan.settimeout(120)
        chan.exec_command("bash -lc 'sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip'")
        time.sleep(0.5)
        chan.send(pw + "\n")
        deadline = time.time() + 120
        buf = b""
        while time.time() < deadline:
            try:
                if chan.recv_ready(): buf += chan.recv(8192)
            except Exception: break
            if chan.exit_status_ready(): break
            time.sleep(0.3)
        rc2 = chan.recv_exit_status() if chan.exit_status_ready() else -1
        print("install_rc", rc2)
        print(buf.decode("utf-8","replace").replace("\ufeff","").encode("ascii","replace").decode("ascii")[-600:])
    else:
        print("PASSWORD_DOES_NOT_WORK_FOR_SMART")

_, o, _ = c.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt; echo; B=/usr/local/share/claude-client; echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1||true); echo scan=$(grep -c 'Default User' $B/editor-launch.ps1||true)")
print(o.read().decode())
c.close()
