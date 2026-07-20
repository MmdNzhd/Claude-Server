$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\bump-connect-version.ps1"
$KeepRepo = '20260719.1'
$FreezeVer = '20260717.22'
$clientRoot = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260719'
Write-Host ("PKG=" + (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim())

# Call deploy-smart-bundle which hardcodes DeploySepidz false
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\deploy-smart-bundle.ps1" `
  -ProjectRoot $root `
  -SmartClientRoot $clientRoot
if ($LASTEXITCODE -ne 0) { throw 'Smart deploy failed' }

Set-ConnectVersionInRepo -ProjectRoot $root -Version $KeepRepo
Write-Host ("REPO_RESTORED=" + (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim())

function SshOut($t,$c){
  $o=Join-Path $env:TEMP ('v'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if(-not $p.WaitForExit(20000)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
}
$smart = SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'
$sepidz = SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'
Write-Host "SMART_LIVE=$smart"
Write-Host "SEPIDZ_LIVE=$sepidz"
if ($smart -ne $FreezeVer) { throw "Smart live is $smart want $FreezeVer" }
Write-Host 'SMART_FREEZE_OK'
