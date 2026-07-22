$ErrorActionPreference='Stop'
$pack = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260720\windows'
$ver = (Get-Content "$pack\connect-version.txt" -Raw).Trim()
$win = Get-Content "$pack\connect.ps1" -Raw
$gm = Get-Content "$pack\git-mode.ps1" -Raw
$ui = Get-Content "$pack\connect-ui.ps1" -Raw
$ok = $true
function Check($c,$m){ if($c){ Write-Host "PASS $m" -ForegroundColor Green } else { Write-Host "FAIL $m" -ForegroundColor Red; $script:ok=$false } }
Check ($ver -eq '20260720.12') "pack ver=$ver"
Check ($win -match "(?m)^\`$script:ConnectVersion = '20260720\.12'\s*$") 'pack ConnectVersion clean'
Check ($win -notmatch 'ConnectVersion\$script:ConnectVersion') 'pack no doubled version'
Check ($gm -match '\[int\]\$TunnelPid') 'pack TunnelPid'
Check ($gm -notmatch '(?s)function Write-TunnelDropLog\s*\{[^}]{0,300}\[int\]\$Pid\s*=') 'pack no Pid'
Check ($win -match '-TunnelPid\s+\$bgPid') 'pack -TunnelPid'
Check ($ui -match 'AllowEmptyString') 'pack AllowEmptyString'
Check ($gm -match 'if \(\$StopEditor -and \$EditorCmd') 'pack StopEditor'
Check ($ui -match 'Get-WindowsSystemProxy|Apply-ConnectProxyEnvironment') 'pack proxy'
$tok=$null;$err=$null
$null=[Management.Automation.Language.Parser]::ParseFile("$pack\connect.ps1",[ref]$tok,[ref]$err)
Check ((-not $err) -or $err.Count -eq 0) 'pack connect.ps1 parses'
if (-not $ok) { exit 1 }
Write-Host 'ALL PACK CHECKS OK' -ForegroundColor Green
exit 0
