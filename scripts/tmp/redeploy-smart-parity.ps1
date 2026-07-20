$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')
$stage=Join-Path $env:TEMP 'claude-bundle-smart-parity'
$zip=Join-Path $env:TEMP 'claude-client-bundle-smart-parity.zip'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$null=New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mac'),(Join-Path $stage 'server\cursor-rules'),(Join-Path $stage 'server\skills\laptop-exec'),(Join-Path $stage 'server\cursor-hooks')
$copies=@(
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
foreach($pair in $copies){
  $src=Join-Path $root $pair[0]; $dst=Join-Path $stage $pair[1]
  if(-not(Test-Path $src)){ throw "missing $src" }
  $parent=Split-Path $dst -Parent; if(-not(Test-Path $parent)){ $null=New-Item -ItemType Directory -Force -Path $parent }
  Copy-Item $src $dst -Force
}
Get-ChildItem $stage -Recurse -File | ForEach-Object { $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/') } | Sort-Object | Set-Content (Join-Path $stage 'manifest.txt') -Encoding ascii
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if(Test-Path $zip){Remove-Item $zip -Force}
$z=[IO.Compression.ZipFile]::Open($zip,'Create')
try{ Get-ChildItem $stage -Recurse -File | ForEach-Object { $rel=$_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/'); $e=$z.CreateEntry($rel); $o=$e.Open(); try{ $fs=[IO.File]::OpenRead($_.FullName); try{$fs.CopyTo($o)} finally{$fs.Dispose()} } finally{$o.Dispose()} } } finally{$z.Dispose()}
$ver=(Get-Content (Join-Path $stage 'connect-version.txt') -Raw).Trim()
$server='smart@192.168.210.240'
Write-Host "deploy Smart v$ver"
& ssh -o BatchMode=yes -o ConnectTimeout=15 $server 'mkdir -p ~/claude-client-bundle-deploy'
& scp -o BatchMode=yes -o ConnectTimeout=60 -q $zip "${server}:~/claude-client-bundle-deploy/bundle.zip"
$remote=@'
set -e
sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$HOME/claude-client-bundle-deploy/bundle.zip"
test -f /usr/local/share/claude-client/connect-diagnostic.ps1
echo VER=$(tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt)
echo HAS_DIAG=yes
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
& ssh -o BatchMode=yes -o ConnectTimeout=90 $server "echo $b64 | base64 -d | bash"
Write-Host "SMART_REDEPLOY_EXIT=$LASTEXITCODE"
