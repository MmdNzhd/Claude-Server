$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10

@(
  'scripts\server\claude-self-heal.sh',
  'scripts\server\claude-automount.sh',
  'scripts\server\laptop-exec-setup.sh',
  'scripts\server\commands\deploy-laptop-exec.sh'
) | ForEach-Object {
  scp -o BatchMode=yes -q (Join-Path $root $_) ("sepidz@192.168.250.70:/tmp/" + [IO.Path]::GetFileName($_))
}

$py = @'
import os, pwd, subprocess, shutil

def write_lf(src, dst, mode=0o755):
    data = open(src, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "wb").write(data)
    os.chmod(dst, mode)
    print("installed", dst)

write_lf("/tmp/claude-self-heal.sh", "/usr/local/bin/claude-self-heal")
write_lf("/tmp/laptop-exec-setup.sh", "/usr/local/bin/laptop-exec-setup")
write_lf("/tmp/claude-automount.sh", "/usr/local/lib/claude-automount")
# common locations for automount
for dst in (
    "/usr/local/bin/claude-automount",
    "/etc/profile.d/claude-automount.sh",
):
    if os.path.exists(dst) or dst.endswith("claude-automount"):
        try:
            write_lf("/tmp/claude-automount.sh", dst)
        except Exception as e:
            print("skip", dst, e)

# also update per-user automount copies if any
for ent in pwd.getpwall():
    if ent.pw_uid < 1000:
        continue
    for rel in (".local/bin/claude-automount", ".bashrc.d/claude-automount.sh"):
        p = os.path.join(ent.pw_dir, rel)
        if os.path.isfile(p):
            write_lf("/tmp/claude-automount.sh", p)
            try:
                os.chown(p, ent.pw_uid, ent.pw_gid)
            except OSError:
                pass

# deploy script archive
for cand in (
    "/usr/local/lib/claude-server/commands/deploy-laptop-exec.sh",
    "/usr/local/lib/claude-server/claude-self-heal.sh",
):
    src = "/tmp/" + os.path.basename(cand.replace("commands/", ""))
    if "deploy" in cand:
        src = "/tmp/deploy-laptop-exec.sh"
    if "self-heal" in cand:
        src = "/tmp/claude-self-heal.sh"
    if os.path.isdir(os.path.dirname(cand)):
        write_lf(src, cand)

# also store self-heal under lib
write_lf("/tmp/claude-self-heal.sh", "/usr/local/lib/claude-server/claude-self-heal.sh")

# Run heal for every human user
ok = fail = 0
for ent in pwd.getpwall():
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody", "nfsnobody"):
        continue
    if not os.path.isdir(ent.pw_dir):
        continue
    # skip users without connect or cursor (optional) — still heal if home exists
    r = subprocess.run(
        ["sudo", "-u", ent.pw_name, "-H", "/usr/local/bin/claude-self-heal"],
        text=True, capture_output=True, timeout=60,
    )
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    print(f"=== {ent.pw_name} ec={r.returncode}")
    if out:
        for line in out.splitlines()[-8:]:
            print(" ", line)
    if r.returncode == 0:
        ok += 1
    else:
        fail += 1

# verify zahrak mounts gone if tunnel down
import re
zhome = "/home/zahrak/mounts"
if os.path.isdir(zhome):
    mounted = []
    for mid in os.listdir(zhome):
        mp = os.path.join(zhome, mid)
        with open("/proc/mounts") as f:
            if any(mp in ln for ln in f):
                mounted.append(mid)
    print("zahrak_mounted_after", mounted)

# markers
assert os.path.isfile("/usr/local/bin/claude-self-heal")
assert "claude-self-heal" in open("/usr/local/lib/claude-automount").read()
print(f"SELF_HEAL_DEPLOY ok={ok} fail={fail}")
'@
[IO.File]::WriteAllText("$env:TEMP\dsh.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\dsh.py" 'sepidz@192.168.250.70:/tmp/dsh.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/dsh.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\dsh.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\dsh.sh" 'sepidz@192.168.250.70:/tmp/dsh.sh'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/dsh.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\dsh_out.txt" -RedirectStandardError "$env:TEMP\dsh_err.txt"
if (-not $p.WaitForExit(180000)) { try{$p.Kill()}catch{}; throw 'timeout' }
Get-Content "$env:TEMP\dsh_out.txt" | Write-Host
Get-Content "$env:TEMP\dsh_err.txt" -ErrorAction SilentlyContinue | Write-Host
if ($p.ExitCode -ne 0) { exit $p.ExitCode }
Write-Host 'DONE'
