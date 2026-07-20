$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10

foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh", '/tmp/claude-self-heal.sh'),
  @("$root\scripts\server\laptop-exec-setup.sh", '/tmp/laptop-exec-setup.sh'),
  @("$root\scripts\server\claude-automount.sh", '/tmp/claude-automount.sh'),
  @("$root\scripts\server\laptop-exec.sh", '/tmp/laptop-exec.sh'),
  @("$root\scripts\server\claude-mount.sh", '/tmp/claude-mount.sh'),
  @("$root\scripts\tmp\deep_ultra.py", '/tmp/deep_ultra.py')
)) {
  scp -o BatchMode=yes -q $pair[0] ("sepidz@192.168.250.70:" + $pair[1])
}

$py = @'
import os, pwd, subprocess
map_install = {
  "/tmp/claude-self-heal.sh": ["/usr/local/bin/claude-self-heal"],
  "/tmp/laptop-exec-setup.sh": ["/usr/local/bin/laptop-exec-setup"],
  "/tmp/claude-automount.sh": ["/usr/local/bin/claude-automount"],
  "/tmp/laptop-exec.sh": ["/usr/local/bin/laptop-exec", "/usr/local/lib/claude-server/laptop-exec.sh"],
  "/tmp/claude-mount.sh": ["/usr/local/bin/claude-mount", "/usr/local/lib/claude-mount"],
}
for src, dsts in map_install.items():
    data = open(src, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    for dst in dsts:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, "wb").write(data)
        os.chmod(dst, 0o755)
        print("sys", dst, len(data))

for ent in pwd.getpwall():
    if ent.pw_uid < 1000: continue
    home = ent.pw_dir
    if not os.path.isdir(home): continue
    if not (os.path.isdir(f"{home}/.cursor-server") or os.path.isfile(f"{home}/.claude-connect.conf")):
        continue
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    for name in ("claude-self-heal","laptop-exec-setup","claude-automount","laptop-exec","claude-mount"):
        sysp = f"/usr/local/bin/{name}"
        if not os.path.isfile(sysp): continue
        dst = f"{home}/.local/bin/{name}"
        data = open(sysp, "rb").read().replace(b"\r\n", b"\n").replace(b"\r", b"")
        open(dst, "wb").write(data)
        os.chmod(dst, 0o755)
        try: os.chown(dst, ent.pw_uid, ent.pw_gid)
        except OSError: pass
    r = subprocess.run(["sudo","-u",ent.pw_name,"-H","/usr/local/bin/claude-self-heal","--quiet"], capture_output=True, text=True, timeout=90)
    print(f"heal {ent.pw_name} rc={r.returncode}")
print("PUSH_DONE")
'@
[IO.File]::WriteAllText("$env:TEMP\push_mp.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\push_mp.py" 'sepidz@192.168.250.70:/tmp/push_mp.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/push_mp.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\push_mp.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\push_mp.sh" 'sepidz@192.168.250.70:/tmp/push_mp.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/push_mp.sh'

Write-Host '======== RE-RUN DEEP ULTRA ========'
$wrap2 = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_ultra.py' + $nl + 'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\du2.sh", $wrap2)
scp -o BatchMode=yes -q "$env:TEMP\du2.sh" 'sepidz@192.168.250.70:/tmp/du2.sh'
$out = "$env:TEMP\du2_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/du2.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(420000)) { try{$p.Kill()}catch{}; throw 'TIMEOUT' }
$txt = Get-Content $out -Raw
Write-Host $txt
if ($txt -notmatch 'DEEP_ULTRA_GREEN') { throw 'RED' }

$sout = "$env:TEMP\smartv3.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $sout -RedirectStandardError "$sout.err"
[void]$p2.WaitForExit(12000)
$sv = if (Test-Path $sout) { (Get-Content $sout -Raw).Trim() } else { '' }
Write-Host "smart=$sv"
Write-Host 'ALL_DEEP_ULTRA_GREEN'
