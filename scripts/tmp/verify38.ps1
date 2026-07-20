$ErrorActionPreference='Stop'
$clientRoot='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code'
$raw=Get-Content (Join-Path $clientRoot 'windows\connect.ps1') -Raw
$alias=[regex]::Match($raw,'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
$ip=[regex]::Match($raw,'192\.168\.\d+\.\d+').Value
$macAlias=[regex]::Match((Get-Content (Join-Path $clientRoot 'mac\connect.sh') -Raw),'(?m)^ALIAS="([^"]+)"').Groups[1].Value
$ver=(Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
Write-Host "PKG ver=$ver alias=$alias macAlias=$macAlias ip=$ip"
if($alias -ne 'claude-server-sepidz'){throw 'alias'}
if($macAlias -ne 'claude-server-sepidz'){throw 'macalias'}
if($ip -ne '192.168.250.70'){throw 'ip'}
if($ver -ne '20260717.38'){throw 'ver'}

$pkg=Join-Path $env:TEMP 'deep-pkg-38b'
if(Test-Path $pkg){Remove-Item $pkg -Recurse -Force}
Copy-Item $clientRoot $pkg -Recurse -Force
$win=Join-Path $pkg 'windows'; $mac=Join-Path $pkg 'mac'
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
Set-Content (Join-Path $mac 'connect-version.txt') '20260717.8'
$log=Join-Path $env:TEMP 'pkg38b.log'
$p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $win 'connect-update.ps1'),'-ScriptDir',$win) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
if(-not $p.WaitForExit(180000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $log -Raw -ErrorAction SilentlyContinue)+'')
$wv=(Get-Content (Join-Path $win 'connect-version.txt') -Raw).Trim()
$mv=(Get-Content (Join-Path $mac 'connect-version.txt') -Raw).Trim()
$a2=[regex]::Match((Get-Content (Join-Path $win 'connect.ps1') -Raw),'\$Alias\s*=\s*"([^"]+)"').Groups[1].Value
$leakM=[bool](Test-Path (Join-Path $win 'mac'))
$leakS=[bool](Test-Path (Join-Path $win 'server'))
Write-Host "AFTER win=$wv mac=$mv alias=$a2 leakMac=$leakM leakSrv=$leakS"
if($wv -ne '20260717.38'){throw 'winver'}
if($mv -ne '20260717.38'){throw 'macver'}
if($a2 -ne 'claude-server-sepidz'){throw 'alias2'}
if($leakM){throw 'macleak'}
if($leakS){throw 'srvleak'}

Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Directory -Filter 'claude-code-sepidz-*' | ForEach-Object {
  $w=Join-Path $_.FullName 'claude-code\windows'
  if(Test-Path $w){
    Copy-Item (Join-Path $clientRoot 'windows\connect-update.ps1') (Join-Path $w 'connect-update.ps1') -Force
    Write-Host ("HEALED "+$_.Name)
  }
}
function SshOut($t,$c){
  $o=Join-Path $env:TEMP ('x'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=8',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  [void]$p.WaitForExit(15000)
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'').Trim()
}
Write-Host ("SEPIDZ_LIVE="+(SshOut 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host ("SMART_LIVE="+(SshOut 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt'))
Write-Host 'DEEP_FIX_OK'
