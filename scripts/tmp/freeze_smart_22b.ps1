$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\bump-connect-version.ps1"

$KeepRepo = '20260719.1'
$FreezeVer = '20260717.22'
$clientRoot = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260719'
$pkgVer = (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
Write-Host "Using PKG ver=$pkgVer path=$clientRoot"
if ($pkgVer -ne $FreezeVer) {
  # rebuild if needed
  Set-ConnectVersionInRepo -ProjectRoot $root -Version $FreezeVer
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\publish.ps1" -SmartOnly -SkipVersionBump -SkipServerDeploy
  if ($LASTEXITCODE -ne 0) { throw 'publish failed' }
  $pkgVer = (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
  if ($pkgVer -ne $FreezeVer) { throw "still $pkgVer" }
}

& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\deploy-client-bundles.ps1" `
  -ProjectRoot $root `
  -SmartClientRoot $clientRoot `
  -DeploySmart `
  -DeploySepidz:$false
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
$smartIp = SshOut 'smart@192.168.210.240' 'grep ServerIP /usr/local/share/claude-client/connect.ps1 | head -1'
Write-Host "SMART_LIVE=$smart"
Write-Host "SEPIDZ_LIVE=$sepidz"
Write-Host "SMART_IP_LINE=$smartIp"
if ($smart -ne $FreezeVer) { throw "Smart live is $smart want $FreezeVer" }
if ($smartIp -notmatch '192\.168\.210\.240') { throw "Smart IP wrong" }
Write-Host 'SMART_FREEZE_OK'
