$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
$client=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
$stage=Join-Path $env:TEMP 'claude-client-bundle-sepidz-20260717.2'
$zip=Join-Path $env:TEMP 'claude-client-bundle-sepidz-20260717.2.zip'
if (-not (Test-Path $client)) { throw "missing $client" }
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'windows') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mac') | Out-Null
$win=@('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
$mac=@('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh')
foreach($n in $win){ Copy-Item (Join-Path $client "windows\$n") (Join-Path $stage "windows\$n") -Force }
foreach($n in $mac){ Copy-Item (Join-Path $client "mac\$n") (Join-Path $stage "mac\$n") -Force }
foreach($s in @('scripts\server\laptop-exec.sh','scripts\server\laptop-exec-setup.sh','scripts\server\claude-mount.sh','scripts\server\claude-git-setup.sh')){
  $src=Join-Path $root $s
  if(Test-Path $src){ Copy-Item $src (Join-Path $stage (Split-Path $s -Leaf)) -Force }
}
foreach($e in @(
 @{Src='scripts\server\cursor-rules\laptop-exec.mdc'; Dst='cursor-rules\laptop-exec.mdc'},
 @{Src='scripts\server\skills\laptop-exec\SKILL.md'; Dst='skills\laptop-exec\SKILL.md'},
 @{Src='scripts\server\cursor-hooks\laptop-exec-guard.sh'; Dst='cursor-hooks\laptop-exec-guard.sh'},
 @{Src='scripts\server\cursor-hooks\hooks-user.json'; Dst='cursor-hooks\hooks-user.json'}
)){
  $src=Join-Path $root $e.Src
  if(Test-Path $src){ $dst=Join-Path $stage $e.Dst; New-Item -ItemType Directory -Force -Path (Split-Path $dst)|Out-Null; Copy-Item $src $dst -Force }
}
if(Test-Path $zip){ Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip)
Write-Output "ZIP=$zip"
Write-Output ("VER=" + (Get-Content (Join-Path $client 'windows\connect-version.txt') -Raw).Trim())
Write-Output ("SIZE=" + (Get-Item $zip).Length)
Write-Output ("has70=" + [bool](Select-String -Path (Join-Path $client 'windows\connect.ps1') -Pattern '192.168.250.70' -Quiet))
Write-Output ("has240=" + [bool](Select-String -Path (Join-Path $client 'windows\connect.ps1') -Pattern '192.168.210.240' -Quiet))
