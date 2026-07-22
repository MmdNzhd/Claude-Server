$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
& (Join-Path $root 'publish\publish.ps1') -SmartOnly -SkipVersionBump
$pub=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'
foreach($t in @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows')
)){
  foreach($f in @('connect.bat','connect-boot.ps1','connect-version.txt','connect-update.ps1','connect.ps1','connect-ui.ps1','git-mode.ps1','editor-launch.ps1','cursor-auth-laptop.ps1','connect-diagnostic.ps1')){
    $src=Join-Path $pub $f; if(Test-Path $src){ Copy-Item $src (Join-Path $t $f) -Force }
  }
  $raw=Get-Content (Join-Path $t 'git-mode.ps1') -Raw
  Write-Host ("SYNC {0} ver={1} comma_return={2} normalize={3}" -f $t,(Get-Content (Join-Path $t 'connect-version.txt') -Raw).Trim(),[int]($raw -match 'return ,\$set'),[int]($raw -match 'openSet -isnot'))
}
