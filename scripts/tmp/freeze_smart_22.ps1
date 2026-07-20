$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\bump-connect-version.ps1"
. "$root\publish\Get-DeployCredentials.ps1"

$KeepRepo = '20260719.1'
$FreezeVer = '20260717.22'
Write-Host "Freeze Smart to $FreezeVer ; keep repo/Sepidz at $KeepRepo"

# 1) Stamp freeze version, publish Smart only (no server deploy from publish)
Set-ConnectVersionInRepo -ProjectRoot $root -Version $FreezeVer
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\publish.ps1" -SmartOnly -SkipVersionBump -SkipServerDeploy
if ($LASTEXITCODE -ne 0) { throw 'publish Smart failed' }

$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$smartDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-client-*' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $smartDir) { throw 'Smart publish folder missing' }
$clientRoot = $smartDir.FullName
# publish smart layout: folder IS the client root (windows/mac under it) OR claude-code subfolder?
$win = Join-Path $clientRoot 'windows'
if (-not (Test-Path $win)) {
  $alt = Join-Path $clientRoot 'claude-code\windows'
  if (Test-Path $alt) { $clientRoot = Join-Path $clientRoot 'claude-code'; $win = $alt }
}
$pkgVer = (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
$ip = [regex]::Match((Get-Content (Join-Path $clientRoot 'windows\connect.ps1') -Raw), '192\.168\.\d+\.\d+').Value
$alias = [regex]::Match((Get-Content (Join-Path $clientRoot 'windows\connect.ps1') -Raw), '\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
Write-Host "PKG path=$clientRoot ver=$pkgVer ip=$ip alias=$alias"
if ($pkgVer -ne $FreezeVer) { throw "pkg ver $pkgVer" }
if ($ip -ne '192.168.210.240') { throw "ip $ip" }
if ($alias -ne 'claude-server') { throw "alias $alias (Smart must stay claude-server)" }

# 2) Deploy Smart only
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\publish\deploy-client-bundles.ps1" `
  -ProjectRoot $root `
  -SmartClientRoot $clientRoot `
  -DeploySmart:$true `
  -DeploySepidz:$false
if ($LASTEXITCODE -ne 0) { throw 'Smart deploy failed' }

# 3) Restore repo version for Sepidz/current line
Set-ConnectVersionInRepo -ProjectRoot $root -Version $KeepRepo
$repoNow = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
Write-Host "REPO_RESTORED=$repoNow"

# 4) Verify lives (Start-Process; no & ssh hang)
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
if ($sepidz -ne $KeepRepo) { Write-Host "WARN Sepidz=$sepidz (expected $KeepRepo; not modified by this script)" }
if ($smartIp -notmatch '192\.168\.210\.240') { throw "Smart IP wrong: $smartIp" }
Write-Host 'SMART_FREEZE_OK'
