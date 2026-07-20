# -*- coding: utf-8 -*-
import os, sys, time, pathlib, subprocess, tempfile, re
import paramiko

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
DESK = pathlib.Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish" / "claude-code-client-20260717"
KEY = pathlib.Path(os.environ["USERPROFILE"]) / ".ssh" / "id_ed25519"
EXPECT = "20260717.2"

# Rebuild correct zip using helper from previous approach (inline minimal)
stage = pathlib.Path(tempfile.gettempdir()) / "claude-stage-smart2"
zip_path = pathlib.Path(tempfile.gettempdir()) / "claude-bundle-smart2.zip"
helper = pathlib.Path(tempfile.gettempdir()) / "build-smart2.ps1"
helper.write_text(rf"""
$ErrorActionPreference='Stop'
$ProjectRoot='{ROOT}'
$ClientRoot='{DESK}'
$StageDir='{stage}'
$ZipPath='{zip_path}'
$WinBundleFiles=@('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
$MacBundleFiles=@('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh')
$ServerBundleFiles=@('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')
function Copy-PublishedFile($Src,$Dst){{ $d=Split-Path $Dst -Parent; if($d -and -not(Test-Path $d)){{New-Item -ItemType Directory -Force -Path $d|Out-Null}}; Copy-Item -LiteralPath $Src -Destination $Dst -Force }}
if(Test-Path $StageDir){{Remove-Item $StageDir -Recurse -Force}}
New-Item -ItemType Directory -Force -Path $StageDir,(Join-Path $StageDir 'mac'),(Join-Path $StageDir 'server')|Out-Null
foreach($n in $WinBundleFiles){{ Copy-PublishedFile (Join-Path $ClientRoot "windows\$n") (Join-Path $StageDir $n) }}
foreach($n in $MacBundleFiles){{ Copy-PublishedFile (Join-Path $ClientRoot "mac\$n") (Join-Path $StageDir "mac\$n") }}
foreach($rel in $ServerBundleFiles){{ $src=Join-Path $ProjectRoot ("scripts\server\"+($rel -replace '/','\')); Copy-PublishedFile $src (Join-Path $StageDir ("server\"+($rel -replace '/','\'))) }}
if(Test-Path $ZipPath){{Remove-Item $ZipPath -Force}}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::Open($ZipPath,'Create')
try{{ Get-ChildItem $StageDir -Recurse -File | ForEach-Object {{ $rel=$_.FullName.Substring($StageDir.Length).TrimStart('\').Replace('\','/'); [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$_.FullName,$rel,'Optimal') }} }} finally {{ $zip.Dispose() }}
Write-Output 'ZIP_OK'
""", encoding='utf-8')
r = subprocess.run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",str(helper)], capture_output=True, text=True)
print(r.stdout, r.stderr)
assert zip_path.exists()

install = (ROOT/"scripts/server/commands/install-client-bundle.sh").read_bytes().replace(b"\r\n",b"\n")
install_tmp = pathlib.Path(tempfile.gettempdir())/"install-lf.sh"
install_tmp.write_bytes(install)

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=25, allow_agent=False, look_for_keys=False)
sftp=c.open_sftp()
try:
    try: sftp.mkdir("claude-client-bundle-deploy")
    except IOError: pass
    sftp.put(str(zip_path), "claude-client-bundle-deploy/bundle.zip")
    sftp.put(str(install_tmp), "claude-client-bundle-deploy/install-client-bundle.sh")
finally:
    sftp.close()
_,stdout,_=c.exec_command("chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh; sed -i 's/\\r$//' ~/claude-client-bundle-deploy/install-client-bundle.sh; python3 -c \"import zipfile;z=zipfile.ZipFile('/home/smart/claude-client-bundle-deploy/bundle.zip'); print('has_root_connect', 'connect.ps1' in z.namelist()); print('ver', z.read('connect-version.txt').decode().strip())\"")
print(stdout.read().decode())
c.close()

# Open interactive sudo window
title = "Claude bundle install - Smart - ENTER SUDO PASSWORD for smart@"
ssh_cmd = 'ssh -t -o ConnectTimeout=15 smart@192.168.210.240 "chmod +x ~/claude-client-bundle-deploy/install-client-bundle.sh && sudo bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip; echo; echo DONE_EXIT=$?; exec bash"'
subprocess.Popen(["cmd.exe", "/c", f"start \"{title}\" cmd /k \"title {title} && {ssh_cmd}\""], shell=False)
print("Opened interactive sudo window. Polling for version...")

deadline = time.time() + 180
while time.time() < deadline:
    try:
        c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)
        _,stdout,_=c.exec_command("tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
        ver=stdout.read().decode().strip(); c.close()
        print("poll", ver)
        if ver == EXPECT:
            c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            c.connect("192.168.210.240", username="smart", key_filename=str(KEY), timeout=15, allow_agent=False, look_for_keys=False)
            _,stdout,_=c.exec_command(r"B=/usr/local/share/claude-client; echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1); echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1); echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)")
            print(stdout.read().decode().strip()); c.close()
            print("SMART_OK")
            sys.exit(0)
    except Exception as e:
        print("poll_err", e)
    time.sleep(5)
print("SMART_TIMEOUT_WAITING_FOR_SUDO")
sys.exit(1)
