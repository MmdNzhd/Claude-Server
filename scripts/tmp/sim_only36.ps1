$ErrorActionPreference = 'Stop'
$src = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
$sim = Join-Path $env:TEMP 'sepidz-update-sim36'
if(Test-Path $sim){Remove-Item $sim -Recurse -Force}
New-Item -ItemType Directory -Force -Path $sim | Out-Null
Copy-Item (Join-Path $src '*') $sim -Force -Recurse
# ensure latest update script from repo (already in package)
Set-Content (Join-Path $sim 'connect-version.txt') '20260717.8'
Write-Host "BEFORE=$((Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim())"
$log = Join-Path $env:TEMP 'sim36.log'
$err = Join-Path $env:TEMP 'sim36.err'
$p2 = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sim 'connect-update.ps1'),'-ScriptDir',$sim) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
if (-not $p2.WaitForExit(180000)) { try{$p2.Kill()}catch{}; Write-Host '---OUT---'; Get-Content $log -EA SilentlyContinue; Write-Host '---ERR---'; Get-Content $err -EA SilentlyContinue; throw 'SIM TIMEOUT' }
Write-Host '---OUT---'; Get-Content $log -EA SilentlyContinue
Write-Host '---ERR---'; Get-Content $err -EA SilentlyContinue
Write-Host "SIM_EXIT=$($p2.ExitCode)"
$after = (Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim()
$simIp = [regex]::Match((Get-Content (Join-Path $sim 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value
Write-Host "SIM_VER_AFTER=$after SIM_IP_AFTER=$simIp"
$live = ((ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=10 sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
$smart = ((ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=8 smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
Write-Host "SEPIDZ_LIVE=$live SMART_LIVE=$smart"
$bad = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Write-Host ("FOLDER_20260717 ver={0} ip={1}" -f (Get-Content (Join-Path $bad 'connect-version.txt') -Raw).Trim(), [regex]::Match((Get-Content (Join-Path $bad 'connect.ps1') -Raw),'192\.168\.\d+\.\d+').Value)
if ($live -ne '20260717.36') { throw "live $live" }
if ($after -ne '20260717.36') { throw "sim $after" }
if ($simIp -ne '192.168.250.70') { throw "ip $simIp" }
Write-Host 'UPDATE_FIX_OK'
