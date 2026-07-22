$ErrorActionPreference='Continue'
Write-Host '==== LAPTOP LIVE ===='
$cc=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-version.txt'
$repo='D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt'
Write-Host ('Claude-Connect=' + $(if(Test-Path $cc){(Get-Content $cc -Raw).Trim()}else{'MISSING'}))
Write-Host ('repo=' + $(if(Test-Path $repo){(Get-Content $repo -Raw).Trim()}else{'MISSING'}))
$s=Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
if(Test-Path $s){ $j=Get-Content $s -Raw|ConvertFrom-Json; Write-Host ('settings.http.proxy=' + [string]$j.'http.proxy') }
$socks=0;$http=0
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -eq 'ssh.exe' -and $_.CommandLine -match 'claude-server' -and $_.CommandLine -notmatch 'sepidz' } | ForEach-Object {
  $c=[string]$_.CommandLine
  if($c -match '-L\s+127\.0\.0\.1:1908\d:127\.0\.0\.1:10808'){ $socks++ }
  if($c -match '-L\s+127\.0\.0\.1:1918\d:127\.0\.0\.1:10809'){ $http++ }
}
Write-Host ("ssh -L socks_legs=$socks http_legs=$http")
# recent figma log in profile
$logRoot=Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\logs'
$latest=Get-ChildItem $logRoot -Directory -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($latest){
  $fig=Get-ChildItem $latest.FullName -Recurse -Filter '*user-figma*' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2
  foreach($f in $fig){
    Write-Host ('--- '+$f.FullName.Replace($env:LOCALAPPDATA,'%LOCALAPPDATA%')+' ---')
    Get-Content $f.FullName -Tail 5 | ForEach-Object { $_ -replace 'Bearer [A-Za-z0-9._\-]+','Bearer ***' -replace 'figu_[A-Za-z0-9._\-]+','figu_***' }
  }
}
Write-Host 'DONE'
