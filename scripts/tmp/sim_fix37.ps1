$ErrorActionPreference = 'Stop'
$src = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
$fixed = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
$sim = Join-Path $env:TEMP 'sepidz-update-sim37'
if (Test-Path $sim) { Remove-Item $sim -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sim | Out-Null
Copy-Item (Join-Path $src '*') $sim -Force -Recurse
Copy-Item $fixed (Join-Path $sim 'connect-update.ps1') -Force
Set-Content (Join-Path $sim 'connect-version.txt') '20260717.8'
Write-Host "BEFORE=$((Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim())"
$log = Join-Path $env:TEMP 'sim37.log'
$err = Join-Path $env:TEMP 'sim37.err'
$p = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sim 'connect-update.ps1'),'-ScriptDir',$sim) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
if (-not $p.WaitForExit(180000)) { try{$p.Kill()}catch{}; Write-Host (Get-Content $log -Raw -EA SilentlyContinue); throw 'TIMEOUT' }
Write-Host (Get-Content $log -Raw -EA SilentlyContinue)
if (Test-Path $err) { $e=(Get-Content $err -Raw -EA SilentlyContinue); if($e){ Write-Host "ERR:$e" } }
Write-Host "SIM_EXIT=$($p.ExitCode)"
$after = (Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim()
$simIp = [regex]::Match((Get-Content (Join-Path $sim 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
Write-Host "SIM_VER_AFTER=$after SIM_IP_AFTER=$simIp"
if ($after -ne '20260717.36') { throw "expected .36 got $after" }
if ($simIp -ne '192.168.250.70') { throw "ip $simIp" }
Write-Host 'UPDATE_FIX_OK'
