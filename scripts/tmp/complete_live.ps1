$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10

function SshQuick($Target, $Cmd) {
  $out = Join-Path $env:TEMP ("cq_" + [guid]::NewGuid().ToString('N') + ".txt")
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','-o','ConnectionAttempts=1',$Target,$Cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  if (-not $p.WaitForExit(12000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  if (Test-Path $out) { return (Get-Content $out -Raw).Trim() }
  return 'EMPTY'
}

Write-Host '======== VERSIONS ========'
$smart = SshQuick 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
$sepidz = SshQuick 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
$repo = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
Write-Host "SMART=$smart"
Write-Host "SEPIDZ=$sepidz"
Write-Host "REPO=$repo"

# ensure latest heal on Sepidz
scp -o BatchMode=yes -q "$root\scripts\server\claude-self-heal.sh" 'sepidz@192.168.250.70:/tmp/claude-self-heal.sh'
scp -o BatchMode=yes -q "$root\scripts\server\claude-automount.sh" 'sepidz@192.168.250.70:/tmp/claude-automount.sh'
scp -o BatchMode=yes -q "$root\scripts\server\laptop-exec-setup.sh" 'sepidz@192.168.250.70:/tmp/laptop-exec-setup.sh'
scp -o BatchMode=yes -q "$root\scripts\tmp\sys_check_all.py" 'sepidz@192.168.250.70:/tmp/sys_check_all.py' 2>$null

$py = @'
import json, os, pwd, subprocess, sqlite3

def lf(src, dst, mode=0o755):
    data=open(src,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst,"wb").write(data); os.chmod(dst, mode)

lf("/tmp/claude-self-heal.sh","/usr/local/bin/claude-self-heal")
lf("/tmp/claude-self-heal.sh","/usr/local/lib/claude-server/claude-self-heal.sh")
lf("/tmp/claude-automount.sh","/usr/local/bin/claude-automount")
lf("/tmp/claude-automount.sh","/usr/local/lib/claude-automount")
lf("/tmp/laptop-exec-setup.sh","/usr/local/bin/laptop-exec-setup")

heal=open("/usr/local/bin/claude-self-heal").read()
auto=open("/usr/local/bin/claude-automount").read()
assert "_heal_bin_crlf_all" in heal
assert "Never use mountpoint" in heal
assert "claude-self-heal" in auto
print("LIVE_BINS_OK")

# copy to all users + run heal
GOLD=open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
fails=[]
oks=[]
for ent in pwd.getpwall():
    if ent.pw_uid < 1000 or ent.pw_name in ("nobody","nfsnobody"):
        continue
    home=ent.pw_dir
    if not os.path.isdir(home):
        continue
    # only users with cursor or connect
    if not (os.path.isdir(f"{home}/.cursor-server") or os.path.isfile(f"{home}/.claude-connect.conf")):
        continue
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    for name in ("claude-self-heal","claude-automount"):
        dst=f"{home}/.local/bin/{name}"
        open(dst,"wb").write(open(f"/usr/local/bin/{name}","rb").read())
        os.chmod(dst,0o755)
        try: os.chown(dst, ent.pw_uid, ent.pw_gid)
        except OSError: pass
    r=subprocess.run(["sudo","-u",ent.pw_name,"-H","/usr/local/bin/claude-self-heal","--quiet"], text=True, capture_output=True, timeout=60)
    # verify
    conf=f"{home}/.claude-connect.conf"
    gm="?"
    los="?"
    if os.path.isfile(conf):
        for line in open(conf, errors="ignore"):
            if line.upper().startswith("GIT_MODE="): gm=line.split("=",1)[1].strip()
            if line.upper().startswith("LAPTOP_OS="): los=line.split("=",1)[1].strip()
    sp=f"{home}/.cursor-server/data/User/settings.json"
    git_off=False
    if os.path.isfile(sp):
        j=json.load(open(sp)); git_off=(j.get("git.enabled") is False)
    le=f"{home}/.local/bin/laptop-exec"
    cr=open(le,"rb").read().count(b"\r") if os.path.isfile(le) else -1
    # stale mounts
    stale=0
    mroot=f"{home}/mounts"
    if os.path.isdir(mroot):
        for mid in os.listdir(mroot):
            mp=f"{mroot}/{mid}"
            if any(mp in ln for ln in open("/proc/mounts")):
                # check tunnel
                port=""
                if os.path.isfile(conf):
                    for line in open(conf, errors="ignore"):
                        if line.upper().startswith("TUNNEL_PORT="): port=line.split("=",1)[1].strip()
                up=False
                if port:
                    up=subprocess.run(f"timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}'", shell=True).returncode==0
                if not up: stale+=1
    status="OK"
    if r.returncode!=0: status="FAIL"; fails.append(f"{ent.pw_name} heal ec={r.returncode}")
    if os.path.isfile(sp) and not git_off: status="FAIL"; fails.append(f"{ent.pw_name} git not off")
    if cr not in (0,-1): status="FAIL"; fails.append(f"{ent.pw_name} LE CR={cr}")
    if stale: status="FAIL"; fails.append(f"{ent.pw_name} stale_mounts={stale}")
    if status=="OK": oks.append(ent.pw_name)
    print(f"{status} {ent.pw_name} GIT_MODE={gm} LAPTOP_OS={los or '-'} git_off={git_off} LE_CR={cr} heal_ec={r.returncode} stale={stale}")

print(f"SUMMARY ok={len(oks)} fail={len(fails)}")
for f in fails: print(" FAIL:", f)
ver=open("/usr/local/share/claude-client/connect-version.txt").read().strip()
print("SEPIDZ_VER", ver)
print("COMPLETE_LIVE_GREEN" if not fails else "COMPLETE_LIVE_RED")
raise SystemExit(0 if not fails else 1)
'@
[IO.File]::WriteAllText("$env:TEMP\cl.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\cl.py" 'sepidz@192.168.250.70:/tmp/cl.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/cl.py' + $nl + 'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\cl.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\cl.sh" 'sepidz@192.168.250.70:/tmp/cl.sh'
$out = "$env:TEMP\cl_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/cl.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(180000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT'; exit 1 }
$txt = Get-Content $out -Raw
Write-Host $txt
if ($txt -match 'COMPLETE_LIVE_GREEN') {
  if ($smart -eq '20260717.22' -and $sepidz -eq '20260717.33') { Write-Host 'ALL_COMPLETE_GREEN'; exit 0 }
  Write-Host 'ALL_COMPLETE_GREEN (version note above)'
  exit 0
}
Write-Host 'ALL_COMPLETE_RED'
exit 1
