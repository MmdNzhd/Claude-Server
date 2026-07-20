# -*- coding: utf-8 -*-
import os, sys, re, subprocess, tempfile, pathlib
import paramiko

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = pathlib.Path(r"D:\Smart\Claude-Code-Server")
DESK = pathlib.Path(os.environ["USERPROFILE"]) / "Desktop" / "claude-publish"
KEY = pathlib.Path(os.environ["USERPROFILE"]) / ".ssh" / "id_ed25519"
EXPECT = "20260717.2"
INSTALL = ROOT / "scripts" / "server" / "commands" / "install-client-bundle.sh"

def read_pw(file_name, var_name):
    p = ROOT / "publish" / file_name
    if not p.exists():
        return None
    text = p.read_text(encoding="utf-8", errors="replace")
    m = re.search(rf"{var_name}\s*=\s*'([^']*)'", text) or re.search(rf'{var_name}\s*=\s*"([^"]*)"', text)
    return m.group(1) if m else None

def make_zip_via_deploy_script(client_root: pathlib.Path, label: str) -> pathlib.Path:
    """Call Build-AutoUpdateBundleStage from deploy-client-bundles.ps1"""
    stage = pathlib.Path(tempfile.gettempdir()) / f"claude-stage-{label}"
    zip_path = pathlib.Path(tempfile.gettempdir()) / f"claude-bundle-{label}.zip"
    ps = f"""
$ErrorActionPreference='Stop'
$ProjectRoot = '{ROOT}'
. (Join-Path $ProjectRoot 'publish\\deploy-client-bundles.ps1')
# sourcing runs the script body and would deploy - BAD.
"""
    # Can't dot-source the whole file. Extract by invoking a helper ps1 instead.
    helper = pathlib.Path(tempfile.gettempdir()) / f"build-bundle-{label}.ps1"
    helper.write_text(f"""
$ErrorActionPreference='Stop'
$ProjectRoot = @'
{ROOT}
'@
$ClientRoot = @'
{client_root}
'@
$StageDir = @'
{stage}
'@
$ZipPath = @'
{zip_path}
'@
# Inline the needed pieces from deploy-client-bundles.ps1
$WinBundleFiles = @(
  'connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1',
  'connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1'
)
$MacBundleFiles = @(
  'connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh'
)
$ServerBundleFiles = @(
  'laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh',
  'cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md',
  'cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json'
)
function Copy-PublishedFile($Src,$Dst) {{
  $dir = Split-Path $Dst -Parent
  if ($dir -and -not (Test-Path $dir)) {{ New-Item -ItemType Directory -Force -Path $dir | Out-Null }}
  Copy-Item -LiteralPath $Src -Destination $Dst -Force
}}
if (Test-Path $StageDir) {{ Remove-Item $StageDir -Recurse -Force }}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'mac') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'server') | Out-Null
foreach ($name in $WinBundleFiles) {{
  $src = Join-Path $ClientRoot \"windows\\$name\"
  if (-not (Test-Path $src)) {{ throw \"missing $src\" }}
  Copy-PublishedFile $src (Join-Path $StageDir $name)
}}
foreach ($name in $MacBundleFiles) {{
  $src = Join-Path $ClientRoot \"mac\\$name\"
  if (-not (Test-Path $src)) {{ throw \"missing $src\" }}
  Copy-PublishedFile $src (Join-Path $StageDir \"mac\\$name\")
}}
foreach ($rel in $ServerBundleFiles) {{
  $src = Join-Path $ProjectRoot (\"scripts\\server\\\" + ($rel -replace '/', '\\'))
  if (-not (Test-Path $src)) {{ throw \"missing $src\" }}
  Copy-PublishedFile $src (Join-Path $StageDir (\"server\\\" + ($rel -replace '/', '\\')))
}}
$manifest = New-Object System.Collections.Generic.List[string]
foreach ($name in $WinBundleFiles) {{ $manifest.Add($name) | Out-Null }}
foreach ($name in $MacBundleFiles) {{ $manifest.Add(\"mac/$name\") | Out-Null }}
Get-ChildItem (Join-Path $StageDir 'server') -Recurse -File | ForEach-Object {{
  $rel = $_.FullName.Substring((Join-Path $StageDir 'server').Length).TrimStart('\\').Replace('\\','/')
  $manifest.Add(\"server/$rel\") | Out-Null
}}
$manifest | Sort-Object | Set-Content (Join-Path $StageDir 'manifest.txt') -Encoding utf8
if (Test-Path $ZipPath) {{ Remove-Item $ZipPath -Force }}
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Create zip with forward-slash names
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
try {{
  Get-ChildItem $StageDir -Recurse -File | ForEach-Object {{
    $rel = $_.FullName.Substring($StageDir.Length).TrimStart('\\').Replace('\\','/')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel, 'Optimal')
  }}
}} finally {{ $zip.Dispose() }}
# verify flat connect.ps1
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z2 = [IO.Compression.ZipFile]::OpenRead($ZipPath)
try {{
  $names = $z2.Entries | ForEach-Object {{ $_.FullName }}
  if ($names -notcontains 'connect.ps1') {{ throw ('zip missing root connect.ps1: ' + ($names -join ',')) }}
  if ($names -notcontains 'mac/connect.sh') {{ throw 'zip missing mac/connect.sh' }}
  Write-Output ('ZIP_OK entries=' + $names.Count)
}} finally {{ $z2.Dispose() }}
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('VER=' + (Get-Content (Join-Path $StageDir 'connect-version.txt') -Raw).Trim())
""", encoding='utf-8')
    r = subprocess.run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",str(helper)], capture_output=True, text=True)
    print(r.stdout)
    if r.returncode != 0:
        print(r.stderr)
        raise SystemExit(f"build zip failed rc={r.returncode}")
    if not zip_path.exists():
        raise SystemExit("zip not created")
    return zip_path

def connect(host, user):
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, key_filename=str(KEY), timeout=25, banner_timeout=25, auth_timeout=25, allow_agent=False, look_for_keys=False)
    return c

def run(c, cmd, timeout=60, pw=None):
    if pw is None:
        _, stdout, stderr = c.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode("utf-8","replace")
        err = stderr.read().decode("utf-8","replace")
        rc = stdout.channel.recv_exit_status()
        return rc, out, err
    stdin, stdout, stderr = c.exec_command(cmd, timeout=timeout, get_pty=True)
    stdin.write(pw + "\n"); stdin.flush()
    out = stdout.read().decode("utf-8","replace")
    err = stderr.read().decode("utf-8","replace")
    rc = stdout.channel.recv_exit_status()
    return rc, out, err

def deploy(label, host, user, client, pw):
    print(f"\n=== {label} ===")
    z = make_zip_via_deploy_script(client, label.lower())
    # Normalize install script to LF in a temp file
    install_text = INSTALL.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    install_tmp = pathlib.Path(tempfile.gettempdir()) / "install-client-bundle-lf.sh"
    install_tmp.write_bytes(install_text)

    c = connect(host, user)
    try:
        rc, out, err = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
        print("before", out.strip())
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
        print("install_rc", rc)
        print(safe[-900:])
        rc, out, err = run(c, "tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt")
        ver = out.strip(); print("after", ver)
        rc, out, err = run(c, r"B=/usr/local/share/claude-client; echo auth=$(grep -c Get-CursorAuthTempRoot $B/cursor-auth-laptop.ps1); echo tunnel=$(grep -c 'Test-TunnelBannerIsWindows -Banner \$banner' $B/git-mode.ps1); echo preserve=$(grep -c preserve_open_windows $B/editor-launch.ps1); echo forceMarker=$(grep -c pre_launch_agent_or_new_window $B/editor-launch.ps1)")
        print(out.strip())
        if ver != EXPECT:
            raise SystemExit(f"{label} expected {EXPECT} got {ver}")
        print(f"OK {label}")
    finally:
        c.close()

def main():
    sepid_pw = read_pw("sepidz-deploy.local.ps1", "SepidzSudoPassword")
    smart_pw = read_pw("smart-deploy.local.ps1", "SmartSudoPassword")
    deploy("SEPIDZ", "192.168.250.70", "sepidz", DESK/"claude-code-sepidz-20260717"/"claude-code", sepid_pw)
    try:
        deploy("SMART", "192.168.210.240", "smart", DESK/"claude-code-client-20260717", smart_pw)
    except SystemExit as e:
        print("SMART_FAILED", e)
        # still leave bundle uploaded if connect worked
        sys.exit(2)

if __name__ == "__main__":
    main()
