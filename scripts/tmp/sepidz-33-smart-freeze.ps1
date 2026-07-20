$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\bump-connect-version.ps1')
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

# Repo + Sepidz -> 33 (fixes). Smart stays frozen at 22 (do not redeploy Smart).
$Version = '20260717.33'
Write-Host "=== Set repo version $Version (Sepidz deploy); Smart remains 22 ==="
Set-ConnectVersionInRepo -ProjectRoot $root -Version $Version
$got = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
if ($got -ne $Version) { throw "repo version mismatch $got" }
Write-Host "REPO=$got"

# Ensure connect-update shows status (non-silent) if not already
$upd = Join-Path $root 'scripts\client\windows\connect-update.ps1'
$updRaw = [IO.File]::ReadAllText($upd)
if ($updRaw -notmatch 'Client up to date') {
  $old = @'
$localVer = Get-LocalVersion
if (-not $localVer) { exit 0 }

$ep = Get-ServerEndpoint
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) { exit 0 }

if (-not (Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)) { exit 0 }
'@
  $new = @'
$localVer = Get-LocalVersion
if (-not $localVer) { exit 0 }

$ep = Get-ServerEndpoint
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) {
    Write-UpdateMsg "Client update check skipped (server unreachable or bundle missing)" 'DarkYellow'
    exit 0
}

if (-not (Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)) {
    Write-UpdateMsg "Client up to date (v$localVer)" 'DarkGray'
    exit 0
}
'@
  if ($updRaw.Contains($old)) {
    [IO.File]::WriteAllText($upd, $updRaw.Replace($old, $new))
    Write-Host 'patched connect-update status msgs'
  } else {
    Write-Host 'connect-update anchors missing/already patched - skip'
  }
}

# Ensure deploy-laptop-exec has CRLF sed (already expected)
$dle = [IO.File]::ReadAllText((Join-Path $root 'scripts\server\commands\deploy-laptop-exec.sh'))
if ($dle -notmatch "sed -i 's/\\r\$//' /usr/local/bin/laptop-exec") {
  throw 'deploy-laptop-exec missing CRLF strip - abort'
}

# Build Sepidz zip
$stage = Join-Path $env:TEMP 'claude-bundle-sepidz-33'
$zip = Join-Path $env:TEMP 'claude-client-bundle-sepidz-33.zip'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mac'), (Join-Path $stage 'server\cursor-rules'), (Join-Path $stage 'server\skills\laptop-exec'), (Join-Path $stage 'server\cursor-hooks')
$copies = @(
  @('scripts\client\windows\connect.bat','connect.bat'),
  @('scripts\client\windows\connect-version.txt','connect-version.txt'),
  @('scripts\client\windows\connect.ps1','connect.ps1'),
  @('scripts\client\windows\connect-rider.bat','connect-rider.bat'),
  @('scripts\client\windows\connect-update.ps1','connect-update.ps1'),
  @('scripts\client\windows\connect-diagnostic.ps1','connect-diagnostic.ps1'),
  @('scripts\client\connect-ui.ps1','connect-ui.ps1'),
  @('scripts\client\editor-launch.ps1','editor-launch.ps1'),
  @('scripts\client\git-mode.ps1','git-mode.ps1'),
  @('scripts\client\cursor-auth-laptop.ps1','cursor-auth-laptop.ps1'),
  @('scripts\client\mac\connect.sh','mac\connect.sh'),
  @('scripts\client\mac\connect-update.sh','mac\connect-update.sh'),
  @('scripts\client\windows\connect-version.txt','mac\connect-version.txt'),
  @('scripts\client\git-mode.sh','mac\git-mode.sh'),
  @('scripts\client\connect-ui.sh','mac\connect-ui.sh'),
  @('scripts\client\editor-launch.sh','mac\editor-launch.sh'),
  @('scripts\server\claude-mount.sh','mac\claude-mount.sh'),
  @('scripts\server\laptop-exec.sh','server\laptop-exec.sh'),
  @('scripts\server\laptop-exec-setup.sh','server\laptop-exec-setup.sh'),
  @('scripts\server\claude-mount.sh','server\claude-mount.sh'),
  @('scripts\server\claude-git-setup.sh','server\claude-git-setup.sh'),
  @('scripts\server\cursor-rules\laptop-exec.mdc','server\cursor-rules\laptop-exec.mdc'),
  @('scripts\server\skills\laptop-exec\SKILL.md','server\skills\laptop-exec\SKILL.md'),
  @('scripts\server\cursor-hooks\laptop-exec-guard.sh','server\cursor-hooks\laptop-exec-guard.sh'),
  @('scripts\server\cursor-hooks\hooks-user.json','server\cursor-hooks\hooks-user.json')
)
foreach ($pair in $copies) {
  $src = Join-Path $root $pair[0]
  $dst = Join-Path $stage $pair[1]
  if (-not (Test-Path $src)) { throw "missing $src" }
  $parent = Split-Path $dst -Parent
  if (-not (Test-Path $parent)) { $null = New-Item -ItemType Directory -Force -Path $parent }
  Copy-Item $src $dst -Force
}
# Force LF on shell scripts in stage
Get-ChildItem $stage -Recurse -Include *.sh,*.mdc | ForEach-Object {
  $b = [IO.File]::ReadAllBytes($_.FullName)
  $n = New-Object System.Collections.Generic.List[byte]
  foreach ($x in $b) { if ($x -ne 13) { [void]$n.Add($x) } }
  [IO.File]::WriteAllBytes($_.FullName, $n.ToArray())
}
Get-ChildItem $stage -Recurse -File | ForEach-Object {
  $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
} | Sort-Object | Set-Content (Join-Path $stage 'manifest.txt') -Encoding ascii

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path $zip) { Remove-Item $zip -Force }
$z = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
  Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\', '/')
    $e = $z.CreateEntry($rel)
    $o = $e.Open()
    try {
      $fs = [IO.File]::OpenRead($_.FullName)
      try { $fs.CopyTo($o) } finally { $fs.Dispose() }
    } finally { $o.Dispose() }
  }
} finally { $z.Dispose() }

$server = Get-SepidzServerTarget
Write-Host "=== Deploy SEPIDZ ONLY v$Version -> $server ==="
& ssh -o BatchMode=yes -o ConnectTimeout=15 $server 'mkdir -p ~/claude-client-bundle-deploy'
& scp -o BatchMode=yes -o ConnectTimeout=60 -q $zip "${server}:~/claude-client-bundle-deploy/bundle.zip"
if ($LASTEXITCODE -ne 0) { throw 'scp zip failed' }
# also upload install script + deploy-laptop-exec for full fix
& scp -o BatchMode=yes -o ConnectTimeout=30 -q (Join-Path $root 'scripts\server\commands\install-client-bundle.sh') "${server}:~/claude-client-bundle-deploy/install-client-bundle.sh"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q (Join-Path $root 'scripts\server\commands\deploy-laptop-exec.sh') "${server}:~/claude-client-bundle-deploy/deploy-laptop-exec.sh"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q (Join-Path $root 'scripts\server\laptop-exec.sh') "${server}:~/claude-client-bundle-deploy/laptop-exec.sh"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q (Join-Path $root 'scripts\server\claude-mount.sh') "${server}:~/claude-client-bundle-deploy/claude-mount.sh"

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @"
set -e
PW=`$(echo $pwB64 | base64 -d)
sudo_pw() { printf '%s\n' "`$PW" | sudo -S -p '' "`$@"; }

# normalize CRLF on uploaded scripts
python3 - <<'PY'
from pathlib import Path
for name in ['install-client-bundle.sh','deploy-laptop-exec.sh','laptop-exec.sh','claude-mount.sh']:
    p = Path.home()/'claude-client-bundle-deploy'/name
    if not p.exists():
        continue
    b = p.read_bytes()
    if b.startswith(b'\xef\xbb\xbf'): b=b[3:]
    p.write_bytes(b.replace(b'\r\n',b'\n').replace(b'\r',b'\n'))
    p.chmod(0o755)
PY

# install golden installer + bundle via sudo -n if possible else password
sudo_pw mkdir -p /usr/local/lib/claude-server/commands /usr/local/lib/claude-server
sudo_pw cp -f "`$HOME/claude-client-bundle-deploy/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh
sudo_pw chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh

if sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "`$HOME/claude-client-bundle-deploy/bundle.zip"; then
  echo BUNDLE_INSTALL=nopasswd
else
  printf '%s\n' "`$PW" | sudo -S -p '' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "`$HOME/claude-client-bundle-deploy/bundle.zip"
  echo BUNDLE_INSTALL=password
fi
echo VER=`$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)

# Push laptop-exec + claude-mount to live paths (CRLF-safe)
sudo_pw cp -f "`$HOME/claude-client-bundle-deploy/laptop-exec.sh" /usr/local/lib/claude-server/laptop-exec.sh
sudo_pw cp -f "`$HOME/claude-client-bundle-deploy/claude-mount.sh" /usr/local/lib/claude-server/claude-mount.sh
sudo_pw cp -f /usr/local/lib/claude-server/laptop-exec.sh /usr/local/bin/laptop-exec
sudo_pw cp -f /usr/local/lib/claude-server/claude-mount.sh /usr/local/lib/claude-mount
sudo_pw ln -sfn /usr/local/lib/claude-mount /usr/local/bin/claude-mount
sudo_pw sed -i 's/\r`$//' /usr/local/bin/laptop-exec /usr/local/lib/claude-server/laptop-exec.sh /usr/local/lib/claude-mount /usr/local/lib/claude-server/claude-mount.sh
sudo_pw chmod 755 /usr/local/bin/laptop-exec /usr/local/lib/claude-mount

# copy to all users
for h in /home/*; do
  u=`$(basename "`$h")
  id "`$u" >/dev/null 2>&1 || continue
  sudo_pw mkdir -p "`$h/.local/bin"
  sudo_pw cp -f /usr/local/bin/laptop-exec "`$h/.local/bin/laptop-exec"
  sudo_pw chown "`$u:`$u" "`$h/.local/bin/laptop-exec"
  sudo_pw chmod 755 "`$h/.local/bin/laptop-exec"
  sudo_pw sed -i 's/\r`$//' "`$h/.local/bin/laptop-exec"
done
echo LAPTOP_EXEC_PUSHED=yes

# sync cursor auth for active-ish users
for u in farzadb hosseinm hosseinb nimaz aminb alit zahrak; do
  id "`$u" >/dev/null 2>&1 || continue
  sudo_pw claude-server sync-cursor-auth "`$u" >/dev/null 2>&1 || true
done
echo AUTH_SYNCED=yes
"@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
& ssh -o BatchMode=yes -o ConnectTimeout=180 $server "echo $b64 | base64 -d > /tmp/sepidz33.sh && bash /tmp/sepidz33.sh"
if ($LASTEXITCODE -ne 0) { throw "sepidz deploy failed $LASTEXITCODE" }

$sepidzVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$smartVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
Write-Host "SEPIDZ=$sepidzVer SMART=$smartVer REPO=$got"
if ($sepidzVer -ne $Version) { throw "Sepidz version mismatch $sepidzVer" }
if ($smartVer -ne '20260717.22') { Write-Host "WARN Smart is $smartVer (expected freeze 20260717.22)" }
Write-Host 'SEPIDZ_33_SMART_22_OK'
