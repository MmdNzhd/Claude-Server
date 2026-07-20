$ErrorActionPreference='Continue'
Write-Host '==== SMART BUNDLE + CRLF + SUDO-N ===='
$py = @'
import os, subprocess
def sh(c):
  return subprocess.run(c,shell=True,text=True,capture_output=True)
ver=open("/usr/local/share/claude-client/connect-version.txt").read().strip().replace("\r","")
print("VER", ver)
req=["connect.bat","connect.ps1","connect-update.ps1","connect-ui.ps1","connect-diagnostic.ps1","git-mode.ps1","editor-launch.ps1","cursor-auth-laptop.ps1","mac/connect.sh","server/laptop-exec.sh","server/claude-mount.sh"]
miss=[]
for r in req:
  p=f"/usr/local/share/claude-client/{r}"
  print(("OK" if os.path.isfile(p) else "MISS"), r)
  if not os.path.isfile(p): miss.append(r)
for p in ["/usr/local/bin/laptop-exec","/usr/local/lib/claude-mount"]:
  if os.path.isfile(p):
    raw=open(p,"rb").read()
    print(("CRLF" if b"\r" in raw else "LF"), p, len(raw))
    if b"\r" in raw:
      open(p,"wb").write(raw.replace(b"\r\n",b"\n").replace(b"\r",b"\n")); print("FIXED", p)
r=sh("sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh /tmp/nope.zip")
out=(r.stdout or "")+(r.stderr or "")
print("SUDO_N", "ok" if ("not found" in out.lower() or "FAIL" in out or "bundle" in out.lower()) and "password" not in out.lower() else out[:200])
print("MISS_COUNT", len(miss))
import hashlib
for rel in ["connect-update.ps1","server/laptop-exec.sh"]:
  p=f"/usr/local/share/claude-client/{rel}"
  if os.path.isfile(p):
    print("SHA", rel, hashlib.sha256(open(p,"rb").read()).hexdigest()[:16])
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
# smart may need sudo password via sudo-from-laptop path - try nopasswd python first as smart user for readable files
& ssh -o BatchMode=yes -o ConnectTimeout=20 smart@192.168.210.240 "echo $b64 | base64 -d > /tmp/smart_audit.py && python3 /tmp/smart_audit.py"
# local repo version
Write-Host 'REPO' (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
# sha from sepidz for compare
& ssh -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "python3 -c \"import hashlib,os;\\nfor rel in ['connect-update.ps1','server/laptop-exec.sh']:\\n p='/usr/local/share/claude-client/'+rel;\\n print('SEPIDZ_SHA',rel,hashlib.sha256(open(p,'rb').read()).hexdigest()[:16] if os.path.isfile(p) else 'MISS')\""
# check deploy-laptop-exec has sed crlf
& ssh -o BatchMode=yes -o ConnectTimeout=10 127.0.0.1 'echo skip' 2>$null
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh' -Pattern "sed -i.*\\\\r" | ForEach-Object { Write-Host "DLE_CRLF_STRIP:" $_.Line.Trim() }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1' -Pattern 'up to date|unreachable|Client update' | ForEach-Object { Write-Host "UPDATE_MSG:" $_.Line.Trim() }
Select-String -Path 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' -Pattern 'base64|SudoPassword \|' | ForEach-Object { Write-Host "DEPLOY_PW:" $_.LineNumber $_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)) }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' -Pattern '_apply_git_scm_policy|git.enabled' | ForEach-Object { Write-Host "MOUNT_GIT:" $_.Line.Trim() }
