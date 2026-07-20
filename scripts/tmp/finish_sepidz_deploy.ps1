$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

$expected = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
Write-Host "EXPECTED=$expected"

$sepidDir = Join-Path $env:USERPROFILE "Desktop\claude-publish\claude-code-sepidz-20260718\claude-code"
if (-not (Test-Path $sepidDir)) {
  # fallback newest sepidz folder
  $sepidDir = Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop\claude-publish') -Directory -Filter 'claude-code-sepidz-*' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName 'claude-code' }
}
if (-not (Test-Path $sepidDir)) { throw "Sepidz package folder not found" }
Write-Host "CLIENT_ROOT=$sepidDir"
Write-Host "client version file=$((Get-Content (Join-Path $sepidDir 'windows\connect-version.txt') -Raw).Trim())"

# Deploy Sepidz ONLY via existing script (uses stored password, never prompts)
& "$root\publish\deploy-client-bundles.ps1" `
  -ProjectRoot $root `
  -SepidClientRoot $sepidDir `
  -DeploySmart:$false `
  -DeploySepidz:$true

if ($LASTEXITCODE -ne 0) { throw "deploy-client-bundles failed: $LASTEXITCODE" }

# Verify Sepidz got new version; Smart untouched
$sepVer = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$smartOut = "$env:TEMP\smart_ver_chk.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','smart@192.168.210.240','tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $smartOut -RedirectStandardError "$smartOut.err"
[void]$p.WaitForExit(15000)
$smartVer = if (Test-Path $smartOut) { (Get-Content $smartOut -Raw).Trim() } else { '?' }

Write-Host "SEPIDZ_LIVE=$sepVer"
Write-Host "SMART_LIVE=$smartVer (must stay 20260717.22)"

if ($sepVer -ne $expected) { throw "Sepidz version mismatch: got $sepVer expected $expected" }
if ($smartVer -ne '20260717.22') { Write-Host "WARN Smart changed unexpectedly to $smartVer" }

# Also refresh critical server bins from repo (heal/mountpoint fixes) without touching Smart
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh", '/tmp/claude-self-heal.sh'),
  @("$root\scripts\server\laptop-exec-setup.sh", '/tmp/laptop-exec-setup.sh'),
  @("$root\scripts\server\claude-automount.sh", '/tmp/claude-automount.sh'),
  @("$root\scripts\server\laptop-exec.sh", '/tmp/laptop-exec.sh'),
  @("$root\scripts\server\claude-mount.sh", '/tmp/claude-mount.sh')
)) {
  scp -o BatchMode=yes -q $pair[0] ("sepidz@192.168.250.70:" + $pair[1])
}
$py = @'
import os, pwd
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
        print("ok", dst)
for ent in pwd.getpwall():
    if ent.pw_uid < 1000: continue
    home = ent.pw_dir
    if not os.path.isdir(home): continue
    if not (os.path.isdir(f"{home}/.cursor-server") or os.path.isfile(f"{home}/.claude-connect.conf")): continue
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    for name in ("claude-self-heal","laptop-exec-setup","claude-automount","laptop-exec","claude-mount"):
        sysp=f"/usr/local/bin/{name}"
        if not os.path.isfile(sysp): continue
        dst=f"{home}/.local/bin/{name}"
        open(dst,"wb").write(open(sysp,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b""))
        os.chmod(dst,0o755)
        try: os.chown(dst, ent.pw_uid, ent.pw_gid)
        except OSError: pass
print("BINS_REFRESHED")
'@
[IO.File]::WriteAllText("$env:TEMP\fin_bins.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\fin_bins.py" 'sepidz@192.168.250.70:/tmp/fin_bins.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/fin_bins.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\fin_bins.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\fin_bins.sh" 'sepidz@192.168.250.70:/tmp/fin_bins.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/fin_bins.sh'

Write-Host 'SEPIDZ_DEPLOY_DONE'
