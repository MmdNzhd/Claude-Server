$ErrorActionPreference='Continue'
$py = @'
import os, hashlib, subprocess
ver=open("/usr/local/share/claude-client/connect-version.txt").read().strip().replace("\r","")
print("SMART_VER", ver)
req=["connect.bat","connect.ps1","connect-update.ps1","connect-ui.ps1","connect-diagnostic.ps1","git-mode.ps1","editor-launch.ps1","cursor-auth-laptop.ps1","mac/connect.sh","server/laptop-exec.sh","server/claude-mount.sh","manifest.txt"]
miss=0
for r in req:
  ok=os.path.isfile(f"/usr/local/share/claude-client/{r}")
  print(("OK" if ok else "MISS"), r)
  miss += 0 if ok else 1
for p in ["/usr/local/bin/laptop-exec","/usr/local/lib/claude-mount"]:
  raw=open(os.path.realpath(p),"rb").read()
  print(("CRLF" if b"\r" in raw else "LF"), p, len(raw))
r=subprocess.run("sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh /tmp/nope.zip",shell=True,text=True,capture_output=True)
out=(r.stdout or "")+(r.stderr or "")
print("SUDO_N", "PASS" if ("not found" in out.lower() or "FAIL" in out) and "password" not in out.lower() else ("FAIL:"+out[:180]))
for rel in ["connect-update.ps1","server/laptop-exec.sh"]:
  p=f"/usr/local/share/claude-client/{rel}"
  print("SMART_SHA", rel, hashlib.sha256(open(p,"rb").read()).hexdigest()[:16])
print("MISS_COUNT", miss)
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
& ssh -o BatchMode=yes -o ConnectTimeout=20 smart@192.168.210.240 "echo $b64 | base64 -d | python3"
$py2 = @'
import os, hashlib
ver=open("/usr/local/share/claude-client/connect-version.txt").read().strip().replace("\r","")
print("SEPIDZ_VER", ver)
for rel in ["connect-update.ps1","server/laptop-exec.sh"]:
  p=f"/usr/local/share/claude-client/{rel}"
  print("SEPIDZ_SHA", rel, hashlib.sha256(open(p,"rb").read()).hexdigest()[:16])
print("SUDOERS", os.path.isfile("/etc/sudoers.d/claude-client-deploy"))
'@
$b642=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py2))
& ssh -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "echo $b642 | base64 -d | python3"
Write-Host 'REPO' (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
Write-Host '--- deploy harden checks ---'
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-laptop-exec.sh' -Pattern "sed -i" | ForEach-Object { 'DLE: ' + $_.Line.Trim() }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1' -Pattern 'up to date|unreachable' | ForEach-Object { 'UPD: ' + $_.Line.Trim() }
Select-String -Path 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' -Pattern 'base64|SudoPassword \|' | ForEach-Object { 'DEP: ' + $_.LineNumber + ' ' + $_.Line.Trim().Substring(0,[Math]::Min(90,$_.Line.Trim().Length)) }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' -Pattern '_apply_git_scm_policy|git.enabled' | ForEach-Object { 'GIT: ' + $_.Line.Trim() }
