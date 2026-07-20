$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

# verify patches locally
$heal = Get-Content "$root\scripts\server\claude-self-heal.sh" -Raw
$setup = Get-Content "$root\scripts\server\laptop-exec-setup.sh" -Raw
$dep = Get-Content "$root\scripts\server\commands\deploy-laptop-exec.sh" -Raw
$checks = @(
  @{N='setup installs self'; Ok=($setup -match 'Keep setup itself in PATH')},
  @{N='setup installs automount'; Ok=($setup -match 'claude-automount')},
  @{N='deploy installs setup to user'; Ok=($dep -match 'laptop-exec-setup "\$h/\.local/bin/laptop-exec-setup"')},
  @{N='deploy installs automount'; Ok=($dep -match 'claude-automount "\$h/\.local/bin/claude-automount"')},
  @{N='heal has missing bins fn'; Ok=($heal -match '_heal_missing_user_bins\(\)')},
  @{N='heal calls missing bins'; Ok=($heal -match '(?m)^_heal_missing_user_bins$')}
)
$fail=0
foreach ($c in $checks) {
  if ($c.Ok) { Write-Host "OK  $($c.N)" } else { Write-Host "FAIL $($c.N)"; $fail++ }
}
if ($fail -ne 0) { throw "local patch verify failed: $fail" }

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh", '/tmp/claude-self-heal.sh'),
  @("$root\scripts\server\laptop-exec-setup.sh", '/tmp/laptop-exec-setup.sh'),
  @("$root\scripts\server\claude-automount.sh", '/tmp/claude-automount.sh')
)) {
  scp -o BatchMode=yes -q $pair[0] ("sepidz@192.168.250.70:" + $pair[1])
}

$py = @'
import os, pwd
files = {
  "/tmp/claude-self-heal.sh": "/usr/local/bin/claude-self-heal",
  "/tmp/laptop-exec-setup.sh": "/usr/local/bin/laptop-exec-setup",
  "/tmp/claude-automount.sh": "/usr/local/bin/claude-automount",
}
for src, dst in files.items():
    data = open(src, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    open(dst, "wb").write(data)
    os.chmod(dst, 0o755)
    print("sys", dst, "bytes", len(data))

# push to all interactive users + run heal
for ent in pwd.getpwall():
    if ent.pw_uid < 1000: continue
    home = ent.pw_dir
    if not os.path.isdir(home): continue
    if not (os.path.isdir(f"{home}/.cursor-server") or os.path.isfile(f"{home}/.claude-connect.conf")):
        continue
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    for name, sysp in (
        ("claude-self-heal", "/usr/local/bin/claude-self-heal"),
        ("laptop-exec-setup", "/usr/local/bin/laptop-exec-setup"),
        ("claude-automount", "/usr/local/bin/claude-automount"),
        ("laptop-exec", "/usr/local/bin/laptop-exec"),
    ):
        if not os.path.isfile(sysp): continue
        dst = f"{home}/.local/bin/{name}"
        data = open(sysp, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"")
        open(dst, "wb").write(data)
        os.chmod(dst, 0o755)
        try: os.chown(dst, ent.pw_uid, ent.pw_gid)
        except OSError: pass
    # run heal as user
    import subprocess
    r = subprocess.run(["sudo", "-u", ent.pw_name, "-H", "/usr/local/bin/claude-self-heal", "--quiet"], capture_output=True, text=True, timeout=90)
    print(f"heal {ent.pw_name} rc={r.returncode}")
print("PUSH_HEAL_DONE")
'@
[IO.File]::WriteAllText("$env:TEMP\push_heal.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\push_heal.py" 'sepidz@192.168.250.70:/tmp/push_heal.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/push_heal.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\push_heal.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\push_heal.sh" 'sepidz@192.168.250.70:/tmp/push_heal.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/push_heal.sh'
