$ErrorActionPreference='Stop'
$srcRoot='D:\Smart\Claude-Code-Server\scripts\client'
$dst=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
if(-not (Test-Path $dst)){ New-Item -ItemType Directory -Force -Path $dst | Out-Null }
# Mirror what connect-update typically needs on Desktop shortcut folder
$map=@(
  @('windows\connect.bat','connect.bat'),
  @('windows\connect.ps1','connect.ps1'),
  @('windows\connect-version.txt','connect-version.txt'),
  @('windows\connect-update.ps1','connect-update.ps1'),
  @('windows\connect-boot.ps1','connect-boot.ps1'),
  @('connect-ui.ps1','connect-ui.ps1'),
  @('editor-launch.ps1','editor-launch.ps1'),
  @('git-mode.ps1','git-mode.ps1'),
  @('cursor-auth-laptop.ps1','cursor-auth-laptop.ps1')
)
foreach($m in $map){
  $s=Join-Path $srcRoot $m[0]
  $d=Join-Path $dst $m[1]
  if(-not (Test-Path $s)){ Write-Host "MISSING_SRC $($m[0])"; continue }
  Copy-Item -LiteralPath $s -Destination $d -Force
  Write-Host "COPIED $($m[1])"
}
$v=(Get-Content (Join-Path $dst 'connect-version.txt') -Raw).Trim()
Write-Host "Claude-Connect version=$v"
# quick markers
$el=Join-Path $dst 'editor-launch.ps1'
$gm=Join-Path $dst 'git-mode.ps1'
foreach($pat in @('http://127.0.0.1:$HttpPort','skip_settings no_http_leg','Get-HttpProxyPort','missing_http','20260721.46')){
  $hit=$false
  foreach($f in @($el,$gm,(Join-Path $dst 'connect-version.txt'),(Join-Path $dst 'connect.ps1'))){
    if((Test-Path $f) -and (Select-String -Path $f -Pattern ([regex]::Escape($pat)) -SimpleMatch -Quiet -EA SilentlyContinue)){ $hit=$true; break }
    if((Test-Path $f) -and (Select-String -Path $f -Pattern $pat -Quiet -EA SilentlyContinue)){ $hit=$true; break }
  }
  if($hit){ Write-Host "PASS $pat" } else { Write-Host "FAIL $pat" }
}
Write-Host 'SYNC_DONE'
