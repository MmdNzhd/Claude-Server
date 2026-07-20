# -*- coding: utf-8 -*-
import pathlib, subprocess, time, sys, zipfile, io, shutil, tempfile
import paramiko
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
DESK = pathlib.Path.home() / "Desktop" / "claude-publish" / "claude-code-client-20260717"
KEY = pathlib.Path.home() / ".ssh" / "id_ed25519"
EXPECT = "20260717.3"
INSTALL_SRC = ROOT / "scripts" / "server" / "commands" / "install-client-bundle.sh"

WIN = ['connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1']
MAC = ['connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh']
SRV = ['laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json']

def build_zip():
    stage = pathlib.Path(tempfile.mkdtemp(prefix="smart-final-"))
    try:
        for n in WIN: shutil.copy2(DESK/"windows"/n, stage/n)
        (stage/"mac").mkdir()
        for n in MAC: shutil.copy2(DESK/"mac"/n, stage/"mac"/n)
        for rel in SRV:
            src = ROOT/"scripts"/"server"/pathlib.Path(*rel.split("/"))
            dst = stage/"server"/pathlib.Path(*rel.split("/"))
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        zpath = pathlib.Path(tempfile.gettempdir())/f"bundle-smart-final-{EXPECT}.zip"
        if zpath.exists(): zpath.unlink()
        with zipfile.ZipFile(zpath,"w",zipfile.ZIP_DEFLATED) as z:
            for fp in stage.rglob("*"):
                if fp.is_file(): z.write(fp, fp.relative_to(stage).as_posix())
        return zpath
    finally:
        shutil.rmtree(stage, ignore_errors=True)

def connect():
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=20, allow_agent=False, look_for_keys=False)
    return c

def ver(c):
    _,o,_=c.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
    return o.read().decode().strip()

def markers(c):
    _,o,_=c.exec_command(r"""B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1||true)
echo scan=$(grep -c 'Default User' $B/editor-launch.ps1||true)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1||true)
echo force=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1||true)
echo diag=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1||true)
""")
    return o.read().decode().strip()

z = build_zip()
print("built", z)
ins = pathlib.Path(tempfile.gettempdir())/"install-lf.sh"
ins.write_bytes(INSTALL_SRC.read_bytes().replace(b"\r\n",b"\n"))

c = connect()
print("BEFORE", markers(c))
sftp = c.open_sftp()
try:
    try: sftp.mkdir("claude-client-bundle-deploy")
    except IOError: pass
    sftp.put(str(z), "claude-client-bundle-deploy/bundle.zip")
    sftp.put(str(ins), "claude-client-bundle-deploy/install-client-bundle.sh")
finally:
    sftp.close()
c.exec_command("chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh; sed -i 's/\\r$//' ~/claude-client-bundle-deploy/install-client-bundle.sh")
c.close()

# Write example local file for password
example = ROOT/"publish"/"smart-deploy.local.ps1.example"
example.write_text("# Copy to smart-deploy.local.ps1 (gitignored) and set password:\n$SmartSudoPassword = 'YOUR_SMART_SUDO_PASSWORD'\n", encoding="utf-8")
print("wrote example", example)

title = "ENTER SMART SUDO PASSWORD - install v20260717.3"
ssh = 'ssh -t -o ConnectTimeout=20 smart@192.168.210.240 "bash ~/install-client-bundle-now.sh; echo; echo DONE_EXIT=$?; exec bash"'
subprocess.Popen(["cmd.exe","/c", f"start \"{title}\" cmd /k \"title {title} && {ssh}\""])
print("Opened interactive window. Polling 2 minutes...")

deadline = time.time() + 120
while time.time() < deadline:
    try:
        c = connect()
        m = markers(c)
        print("poll", m.replace("\n"," | "))
        if f"version={EXPECT}" in m and "scan=1" in m and "auth=2" in m:
            print("SMART_COMPLETE")
            # also verify sepidz
            c2 = paramiko.SSHClient(); c2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            c2.connect("192.168.250.70", username="sepidz", key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)
            _,o,_=c2.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
            print("SEPIDZ", o.read().decode().strip()); c2.close()
            c.close(); sys.exit(0)
        c.close()
    except Exception as e:
        print("poll_err", e)
    time.sleep(5)

print("SMART_STILL_NEEDS_SUDO")
sys.exit(2)
