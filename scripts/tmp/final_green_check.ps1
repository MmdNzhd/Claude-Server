$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))

# local harden checks
Write-Host '=== LOCAL HARDEN ==='
$checks = @(
  @{ File='publish\deploy-client-bundles.ps1'; Pat='base64, non-interactive'; Name='deploy-no-hang' },
  @{ File='publish\deploy-client-bundles.ps1'; Pat='\$SudoPassword \| & ssh'; Name='old-hang-gone'; Neg=$true },
  @{ File='scripts\server\claude-mount.sh'; Pat='_apply_git_scm_policy'; Name='git-scm-policy' },
  @{ File='scripts\client\windows\connect-update.ps1'; Pat='Client up to date'; Name='update-status-msg' },
  @{ File='scripts\server\commands\deploy-laptop-exec.sh'; Pat="sed -i 's/\\r\$//' /usr/local/bin/laptop-exec"; Name='dle-crlf' },
  @{ File='scripts\server\sudoers.d\claude-client-deploy'; Pat='Defaults:sepidz'; Name='sudoers-sepidz' }
)
$root='D:\Smart\Claude-Code-Server'
$localFail=0
foreach($c in $checks){
  $text = Get-Content (Join-Path $root $c.File) -Raw
  $hit = $text -match $c.Pat
  if ($c.ContainsKey('Neg') -and $c.Neg) {
    if ($hit) { Write-Host "FAIL $($c.Name) still present"; $localFail++ } else { Write-Host "OK   $($c.Name)" }
  } else {
    if ($hit) { Write-Host "OK   $($c.Name)" } else { Write-Host "FAIL $($c.Name) missing"; $localFail++ }
  }
}

# versions
Write-Host '=== VERSIONS ==='
$smart = (ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
$sepidz = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
$repo = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
Write-Host "SMART=$smart SEPIDZ=$sepidz REPO=$repo"
if ($smart -ne '20260717.22') { Write-Host 'FAIL Smart freeze broken'; $localFail++ } else { Write-Host 'OK   Smart frozen 22' }
if ($sepidz -ne '20260717.33') { Write-Host 'FAIL Sepidz not 33'; $localFail++ } else { Write-Host 'OK   Sepidz 33' }

# remote deep
$py = @'
import json, os, pwd, sqlite3, subprocess, sys
fails=[]; oks=[]
def ok(m): oks.append(m); print("OK  ", m)
def fail(m): fails.append(m); print("FAIL", m)
def sh(c,t=35):
  return subprocess.run(c,shell=True,text=True,capture_output=True,timeout=t)
GOLD=open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
AUTH=json.load(open("/etc/cursor-auth/golden/auth.json"))
# system
ver=open("/usr/local/share/claude-client/connect-version.txt").read().strip().replace("\r","")
(ok if ver=="20260717.33" else fail)(f"bundle {ver}")
for p in ["/usr/local/bin/laptop-exec","/usr/local/lib/claude-mount"]:
  cr=open(os.path.realpath(p),"rb").read().count(b"\r")
  (ok if cr==0 else fail)(f"{p} CR={cr}")
pol = open("/usr/local/lib/claude-mount","r",encoding="utf-8",errors="ignore").read()
(ok if "_apply_git_scm_policy" in pol else fail)("mount git policy live")
r=sh("sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh /tmp/nope.zip 2>&1")
out=(r.stdout or "")+(r.stderr or "")
(ok if ("not found" in out.lower() or "FAIL" in out) and "password" not in out.lower() else fail)("sudo -n install")

# all users
for line in open("/etc/passwd"):
  parts=line.split(":")
  if len(parts)<6: continue
  u,uid,home=parts[0],int(parts[2]),parts[5]
  if uid<1000 or u=="nobody" or not home.startswith("/home/") or not os.path.isdir(home):
    continue
  le=f"{home}/.local/bin/laptop-exec"
  if os.path.isfile(le):
    cr=open(le,"rb").read().count(b"\r")
    if cr: fail(f"{u} LE CRLF")
  db=f"{home}/.config/Cursor/User/globalStorage/state.vscdb"
  if os.path.isfile(db):
    for lab,p in [("p",f"{home}/.config/Cursor/machineid"),("s",f"{home}/.cursor-server/data/machineid")]:
      if not os.path.isfile(p): fail(f"{u} mid {lab} missing"); continue
      raw=open(p,"rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
      if raw!=GOLD: fail(f"{u} mid {lab} mismatch")
    c=sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    def gv(k):
      r=c.execute("select value from ItemTable where key=?",(k,)).fetchone()
      return "" if not r or r[0] is None else str(r[0])
    if len(gv("cursorAuth/accessToken"))<20 or len(gv("cursorAuth/refreshToken"))<20:
      fail(f"{u} tokens")
    else:
      ok(f"{u} mid+tok OK")
    c.close()

# live IO
live=[]
for line in open("/etc/passwd"):
  parts=line.split(":"); 
  if len(parts)<6: continue
  u,uid,home=parts[0],int(parts[2]),parts[5]
  if uid<1000 or not home.startswith("/home/"): continue
  conf=f"{home}/.claude-connect.conf"
  if not os.path.isfile(conf): continue
  kv={}
  for ln in open(conf):
    if "=" in ln:
      k,v=ln.strip().split("=",1); kv[k]=v
  port=kv.get("TUNNEL_PORT","")
  if not port: continue
  r=sh(f"timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}' && echo open || echo closed")
  if "open" in r.stdout: live.append((u,home,kv))

for u,home,kv in live:
  r=sh(f"timeout 5 su - {u} -c 'echo SHELL_OK'")
  (ok if "SHELL_OK" in r.stdout else fail)(f"{u} shell")
  r=sh(f"su - {u} -c 'laptop-exec status'")
  (ok if "UP" in (r.stdout+r.stderr) else fail)(f"{u} le-status")
  mdir=f"{home}/mounts"
  if not os.path.isdir(mdir): continue
  for name in sorted(os.listdir(mdir)):
    mp=os.path.join(mdir,name)
    if sh(f"mountpoint -q '{mp}' && echo yes || echo no").stdout.find("yes")<0: continue
    r=sh(f"su - {u} -c \"printf green > $HOME/.g.txt && laptop-exec write -p {name} .final-e2e.txt < $HOME/.g.txt && laptop-exec read -p {name} .final-e2e.txt && rm -f $HOME/.g.txt\"")
    if "green" in r.stdout:
      ok(f"{u}/{name} IO")
      sh(f"su - {u} -c 'laptop-exec run -p {name} -- cmd /c del .final-e2e.txt' >/dev/null 2>&1 || true")
    else:
      fail(f"{u}/{name} IO {(r.stderr or r.stdout)[:160]}")
    # git settings if .git
    if os.path.exists(os.path.join(mp,".git")):
      vs=os.path.join(mp,".vscode","settings.json")
      if os.path.isfile(vs):
        try:
          d=json.load(open(vs))
          (ok if d.get("git.enabled") is False else fail)(f"{u}/{name} git.enabled=false")
        except Exception as e:
          fail(f"{u}/{name} settings {e}")

print(f"SUMMARY ok={len(oks)} fail={len(fails)}")
for f in fails: print(" FAIL:", f)
sys.exit(1 if fails else 0)
'@
$pyPath = Join-Path $env:TEMP 'final_green.py'
[IO.File]::WriteAllText($pyPath, $py)
& scp -o BatchMode=yes -q $pyPath 'sepidz@192.168.250.70:/tmp/final_green.py'
$nl=[char]10
$wrap='#!/bin/bash'+$nl+'PW=$(echo '+$pwB64+' | base64 -d)'+$nl+'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/final_green.py'+$nl+'ec=$?'+$nl+'echo FINAL_EXIT=$ec'+$nl+'exit $ec'+$nl
[IO.File]::WriteAllText("$env:TEMP\final_green_wrap.sh",$wrap)
& scp -o BatchMode=yes -q "$env:TEMP\final_green_wrap.sh" 'sepidz@192.168.250.70:/tmp/final_green_wrap.sh'
Write-Host '=== SEPIDZ FINAL ==='
& ssh -o BatchMode=yes -o ConnectTimeout=240 sepidz@192.168.250.70 'bash /tmp/final_green_wrap.sh'
$remoteEc=$LASTEXITCODE
Write-Host "LOCAL_FAIL=$localFail REMOTE_EC=$remoteEc"
if ($localFail -ne 0 -or $remoteEc -ne 0) { exit 1 }
Write-Host 'ALL_GREEN'
exit 0
