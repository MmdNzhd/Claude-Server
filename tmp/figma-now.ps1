$ErrorActionPreference='Continue'
$settings=Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
$proxy='?'
if(Test-Path $settings){
  $j=Get-Content $settings -Raw | ConvertFrom-Json
  $proxy=[string]$j.'http.proxy'
}
Write-Host ("settings_proxy="+$proxy)
$httpL=0
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-L\s+127\.0\.0\.1:1918\d:127\.0\.0\.1:10809'
} | ForEach-Object { $httpL++ }
Write-Host ("http_L_forwards="+$httpL)
# latest figma mcp log error/success
$logRoot=Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\logs'
$latest=Get-ChildItem $logRoot -Directory -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($latest){
  $fig=Get-ChildItem $latest.FullName -Recurse -Filter '*figma*' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 4
  foreach($f in $fig){
    Write-Host ("--- "+$f.Name+" mtime="+$f.LastWriteTime.ToString('HH:mm:ss')+" ---")
    Get-Content $f.FullName -Tail 8 -EA SilentlyContinue | ForEach-Object {
      $_ -replace 'Bearer [A-Za-z0-9._\-]+','Bearer ***' -replace 'figu_[A-Za-z0-9._\-]+','figu_***'
    }
  }
}
