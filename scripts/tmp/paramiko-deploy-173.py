# -*- coding: utf-8 -*-
import os, sys, re, subprocess, tempfile, pathlib, time
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
    stage = pathlib.Path(tempfile.gettempdir()) / f"stage-{label}"
    zpath = pathlib.Path(tempfile.gettempdir()) / f"bundle-{label}-{EXPECT}.zip"
    helper = pathlib.Path(tempfile.gettempdir()) / f"build-{label}.ps1"
    helper.write_text(f"""
$ErrorActionPreference='Stop'
$ProjectRoot='{ROOT}'
$ClientRoot='{client}'
$StageDir='{stage}'
$ZipPath='{zpath}'
$Win=@({','.join("'"+x+"'" for x in WIN)})
$Mac=@({','.join("'"+x+"'" for x in MAC)})
$Srv=@({','.join("'"+x+"'" for x in SRV)})
function Cp($s,$d){{ $p=Split-Path $d -Parent; if($p -and -not(Test-Path $p)){{New-Item -ItemType Directory -Force -Path $p|Out-Null}}; Copy-Item -LiteralPath $s -Destination $d -Force }}
if(Test-Path $StageDir){{Remove-Item $StageDir -Recurse -Force}}
New-Item -ItemType Directory -Force -Path $StageDir,(Join-Path $StageDir 'mac'),(Join-Path $StageDir 'server')|Out-Null
foreach($n in $Win){{ Cp (Join-Path $ClientRoot "windows\\$n") (Join-Path $StageDir $n) }}
foreach($n in $Mac){{ Cp (Join-Path $ClientRoot "mac\\$n") (Join-Path $StageDir "mac\\$n") }}
foreach($rel in $Srv){{ Cp (Join-Path $ProjectRoot ("scripts\\server\\"+($rel -replace '/','\\'))) (Join-Path $StageDir ("server\\"+($rel -replace '/','\\'))) }}
if(Test-Path $ZipPath){{Remove-Item $ZipPath -Force}}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::Open($ZipPath,'Create')
try{{ Get-ChildItem $StageDir -Recurse -File | ForEach-Object {{ $rel=$_.FullName.Substring($StageDir.Length).TrimStart('\\').Replace('\\','/'); [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$_.FullName,$rel,'Optimal') }} }} finally {{ $zip.Dispose() }}
$z=[IO.Compression.ZipFile]::OpenRead($ZipPath)
try {{
  $names=$z.Entries.FullName
  if($names -notcontains 'connect.ps1'){{ throw 'missing root connect.ps1' }}
  if($names -notcontains 'editor-launch.ps1'){{ throw 'missing editor-launch.ps1' }}
}} finally {{ $z.Dispose() }}
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('VER=' + (Get-Content (Join-Path $StageDir 'connect-version.txt') -Raw).Trim())
""", encoding='utf-8')
    r = subprocess.run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",str(helper)], capture_output=True, text=True)
    print(r.stdout)
    if r.returncode != 0:
        print(r.stderr); raise SystemExit(f"build failed {label}")
    return zpath

def connect(host, user):
    c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=25, banner_timeout=25, auth_timeout=25, allow_agent=False, look_for_keys=False)
    return c

def run(c, cmd, timeout=60, pw=None):
    if pw is None:
        _, so, se = c.exec_command(cmd, timeout=timeout)
        out, err = so.read().decode('utf-8','replace'), se.read().decode('utf-8','replace')
        return so.channel.recv_exit_status(), out, err
    stdin, so, se = c.exec_command(cmd, timeout=timeout, get_pty=True)
    stdin.write(pw + "\n"); stdin.flush()
    out, err = so.read().decode('utf-8','replace'), se.read().decode('utf-8','replace')
    return so.channel.recv_exit_status(), out, err

def markers(c):
    cmd = r"""B=/usr/local/share/claude-client
echo version=$(tr -d '\r\n' < $B/connect-version.txt)
echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1)
echo all_users=$(grep -c 'AppData\\Local\\Programs' $B/editor-launch.ps1)
echo scan_users=$(grep -c 'Default User' $B/editor-launch.ps1)
echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1)
echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1)
echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)
echo diag_fix=$(grep -c 'not found for this Windows user' $B/connect-diagnostic.ps1)
"""
    _, so, _ = c.exec_command(cmd, timeout=30)
    return so.read().decode().strip()

def deploy(label, host, user, client, pw):
    print(f"\n=== {label} ===")
    z = build_zip(client, label.lower())
    install_tmp = pathlib.Path(tempfile.gettempdir()) / f"install-{label}.sh"
    install_tmp.write_bytes(INSTALL_SRC.read_bytes().replace(b'\r\n', b'\n').replace(b'\r', b'\n'))
    c = connect(host, user)
    try:
        print("before:", run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")[1].strip())
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
        safe = (out + "\n" + err).replace("\ufeff","").encode("ascii","replace").decode("ascii")
        print("install_rc", rc)
        print(safe[-700:])
        print(markers(c))
        ver = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")[1].strip()
        if ver != EXPECT:
            raise SystemExit(f"{label} still {ver}, want {EXPECT}")
        print(f"OK {label}")
    finally:
        c.close()

def finish_smart_interactive():
    """Open sudo window and poll."""
    title = "SMART sudo - enter password to install v20260717.3"
    ssh = 'ssh -t -o ConnectTimeout=20 smart@192.168.210.240 "sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip; echo DONE_EXIT=$?; exec bash"'
    subprocess.Popen(["cmd.exe", "/c", f"start \"{title}\" cmd /k \"title {title} && {ssh}\""])
    print("Opened Smart sudo window; polling 3 min...")
    deadline = time.time() + 180
    while time.time() < deadline:
        try:
            c = connect("192.168.210.240", "smart")
            ver = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")[1].strip()
            print("poll", ver)
            if ver == EXPECT:
                print(markers(c)); c.close(); return True
            c.close()
        except Exception as e:
            print("poll_err", e)
        time.sleep(5)
    return False

def main():
    sepid_pw = read_pw("sepidz-deploy.local.ps1", "SepidzSudoPassword")
    smart_pw = read_pw("smart-deploy.local.ps1", "SmartSudoPassword")
    deploy("SEPIDZ", "192.168.250.70", "sepidz", DESK/"claude-code-sepidz-20260717"/"claude-code", sepid_pw)
    try:
        deploy("SMART", "192.168.210.240", "smart", DESK/"claude-code-client-20260717", smart_pw)
    except SystemExit as e:
        print("SMART needs sudo:", e)
        if finish_smart_interactive():
            print("SMART_OK via interactive")
            return
        print("SMART_STILL_PENDING_SUDO")
        sys.exit(2)

if __name__ == "__main__":
    main()
