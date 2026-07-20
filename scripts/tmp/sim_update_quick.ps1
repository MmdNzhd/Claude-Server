$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$src = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
$sim = Join-Path $env:TEMP 'sepidz-update-sim2'
if (Test-Path $sim) { Remove-Item $sim -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sim | Out-Null
Copy-Item (Join-Path $src '*') $sim -Force -Recurse
Set-Content (Join-Path $sim 'connect-version.txt') '20260717.8'
Write-Host "BEFORE=$((Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim())"
$log = Join-Path $env:TEMP 'sim-update.log'
$err = Join-Path $env:TEMP 'sim-update.err'
$p = Start-Process powershell -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sim 'connect-update.ps1'),'-ScriptDir',$sim
) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
if (-not $p.WaitForExit(90000)) {
  Write-Host 'TIMEOUT_KILL'
  try { $p.Kill() } catch {}
  Write-Host '--- OUT ---'; Get-Content $log -ErrorAction SilentlyContinue
  Write-Host '--- ERR ---'; Get-Content $err -ErrorAction SilentlyContinue
  exit 2
}
Write-Host "EXIT=$($p.ExitCode)"
Write-Host '--- OUT ---'; Get-Content $log -ErrorAction SilentlyContinue
Write-Host '--- ERR ---'; Get-Content $err -ErrorAction SilentlyContinue
$after = (Get-Content (Join-Path $sim 'connect-version.txt') -Raw).Trim()
$ip = [regex]::Match((Get-Content (Join-Path $sim 'connect.ps1') -Raw), '192\.168\.\d+\.\d+').Value
Write-Host "AFTER=$after IP=$ip"
if ($after -eq '20260717.35' -and $ip -eq '192.168.250.70') { Write-Host 'UPDATE_FIX_OK' } else { Write-Host 'UPDATE_FIX_FAIL'; exit 1 }
