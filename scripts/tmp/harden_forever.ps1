$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10

# push updated files
scp -o BatchMode=yes -q "$root\scripts\server\claude-mount.sh" 'sepidz@192.168.250.70:/tmp/claude-mount.new'
scp -o BatchMode=yes -q "$root\scripts\server\laptop-exec-setup.sh" 'sepidz@192.168.250.70:/tmp/laptop-exec-setup.new'
scp -o BatchMode=yes -q "$root\scripts\server\commands\deploy-laptop-exec.sh" 'sepidz@192.168.250.70:/tmp/deploy-laptop-exec.new'

$py = @'
import json, os, pwd, subprocess

# install binaries
for src, dst, mode in [
 ("/tmp/claude-mount.new", "/usr/local/lib/claude-mount", 0o755),
 ("/tmp/laptop-exec-setup.new", "/usr/local/bin/laptop-exec-setup", 0o755),
]:
    data = open(src, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    open(dst, "wb").write(data)
    os.chmod(dst, mode)
    print("installed", dst)

# also keep deploy script under server dir if present
for cand in ("/usr/local/lib/claude-server/commands/deploy-laptop-exec.sh", "/opt/claude-server/scripts/server/commands/deploy-laptop-exec.sh"):
    if os.path.isdir(os.path.dirname(cand)) or os.path.isfile(cand):
        data = open("/tmp/deploy-laptop-exec.new", "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        os.makedirs(os.path.dirname(cand), exist_ok=True)
        open(cand, "wb").write(data)
        os.chmod(cand, 0o755)
        print("installed", cand)

want = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}

def merge(path, uid, gid):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        data = json.load(open(path, encoding="utf-8"))
        if not isinstance(data, dict): data = {}
    except Exception:
        data = {}
    data.update(want)
    data.pop("git.path", None)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2); f.write("\n")
    try:
        os.chown(path, uid, gid); os.chown(os.path.dirname(path), uid, gid)
    except OSError:
        pass

n_git = n_le = 0
for ent in pwd.getpwall():
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody", "nfsnobody"):
        continue
    home = ent.pw_dir
    if not os.path.isdir(home):
        continue
    # LE CRLF strip + copy if system has LE
    le_sys = "/usr/local/bin/laptop-exec"
    le_u = os.path.join(home, ".local/bin/laptop-exec")
    if os.path.isfile(le_sys):
        os.makedirs(os.path.join(home, ".local/bin"), exist_ok=True)
        data = open(le_sys, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"")
        open(le_u, "wb").write(data)
        os.chmod(le_u, 0o755)
        try:
            os.chown(le_u, ent.pw_uid, ent.pw_gid)
            os.chown(os.path.dirname(le_u), ent.pw_uid, ent.pw_gid)
        except OSError:
            pass
        n_le += 1
    for rel in (".cursor-server/data/User/settings.json", ".vscode-server/data/User/settings.json"):
        top = os.path.join(home, rel.split("/")[0])
        data_dir = os.path.join(home, *rel.split("/")[:2])
        if os.path.isdir(top) and os.path.isdir(data_dir):
            merge(os.path.join(home, rel), ent.pw_uid, ent.pw_gid)
            n_git += 1

# verify markers
cm = open("/usr/local/lib/claude-mount").read()
su = open("/usr/local/bin/laptop-exec-setup").read()
assert "Only remote User settings" in cm
assert "_ensure_cursor_git_off" in su
assert open("/usr/local/bin/laptop-exec","rb").read().count(b"\r")==0
print(f"HARDENED git_settings={n_git} le_copies={n_le}")

# versions
print("SEPIDZ", open("/usr/local/share/claude-client/connect-version.txt").read().strip())
for u in ("farzadb","hosseinm","hosseinb"):
    j=json.load(open(f"/home/{u}/.cursor-server/data/User/settings.json"))
    assert j.get("git.enabled") is False
    print("OK", u, "git OFF")
print("HARDEN_OK")
'@
[IO.File]::WriteAllText("$env:TEMP\harden.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\harden.py" 'sepidz@192.168.250.70:/tmp/harden.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/harden.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\harden.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\harden.sh" 'sepidz@192.168.250.70:/tmp/harden.sh'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/harden.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\harden_out.txt" -RedirectStandardError "$env:TEMP\harden_err.txt"
if (-not $p.WaitForExit(90000)) { try{$p.Kill()}catch{}; throw 'timeout' }
Get-Content "$env:TEMP\harden_out.txt" | Write-Host
Get-Content "$env:TEMP\harden_err.txt" -ErrorAction SilentlyContinue | Write-Host

# smart version still 22
$out = "$env:TEMP\sv.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=6','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
[void]$p2.WaitForExit(12000)
Write-Host ("SMART=" + (Get-Content $out -Raw).Trim())
Write-Host 'DONE'
