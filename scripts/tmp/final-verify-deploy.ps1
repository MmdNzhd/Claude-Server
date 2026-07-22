#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$script:pass = 0; $script:fail = 0; $script:fails = New-Object System.Collections.Generic.List[string]
function Assert([bool]$c,[string]$m){ if($c){ Write-Host "PASS  $m" -ForegroundColor Green; $script:pass++ } else { Write-Host "FAIL  $m" -ForegroundColor Red; $script:fail++; [void]$script:fails.Add($m) } }

Set-Location D:\Smart\Claude-Code-Server
$ver = (Get-Content scripts/client/windows/connect-version.txt -Raw).Trim()
$gm = Get-Content scripts/client/git-mode.ps1 -Raw
$ui = Get-Content scripts/client/connect-ui.ps1 -Raw
$win = Get-Content scripts/client/windows/connect.ps1 -Raw
$el = Get-Content scripts/client/editor-launch.ps1 -Raw

Write-Host "=== REPO v$ver ===" -ForegroundColor Cyan
Assert ($ver -eq '20260720.12') "repo version=$ver"
Assert ($gm -match '\[int\]\$TunnelPid') 'TunnelPid'
Assert ($gm -notmatch '(?s)function Write-TunnelDropLog\s*\{[^}]{0,300}\[int\]\$Pid\s*=') 'no Pid param'
Assert ($win -match '-TunnelPid\s+\$bgPid') '-TunnelPid call'
Assert ($win -match "(?m)^\`$script:ConnectVersion = '20260720\.12'\s*$") 'ConnectVersion line clean'
Assert ($win -notmatch '\$script:ConnectVersion\$script:ConnectVersion') 'no doubled ConnectVersion'
Assert ($ui -match 'AllowEmptyString') 'AllowEmptyString'
Assert ($ui -match '(?s)LastSessionStatusKey = \$statusKey\s*\r?\n\s*Write-Host \$line') 'status dedupe'
Assert ($gm -match 'if \(\$StopEditor -and \$EditorCmd') 'StopEditor gate'
Assert ($ui -match 'Get-WindowsSystemProxy|Initialize-ConnectProxyForSsh|Apply-ConnectProxyEnvironment') 'proxy helpers'
Assert ($win -match 'Initialize-ConnectProxyForSsh|Apply-ConnectProxyEnvironment') 'proxy wired'
Assert ($el -match 'LAUNCH_FAIL: started_but_no_process') 'launch fail-closed'
Assert ($ui -match 'Global\\ClaudeConnect') 'single-instance'

foreach ($rel in @('scripts/client/git-mode.ps1','scripts/client/connect-ui.ps1','scripts/client/windows/connect.ps1','scripts/client/editor-launch.ps1')) {
  $tok=$null;$err=$null
  $null=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $rel),[ref]$tok,[ref]$err)
  Assert ((-not $err) -or ($err.Count -eq 0)) "parse $rel"
}

$pack = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260720\windows'
Assert (Test-Path $pack) 'desktop pack exists'

Write-Host ("SUMMARY pass=$($script:pass) fail=$($script:fail)") -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
if ($script:fail) { $script:fails | %{ Write-Host "  - $_" -ForegroundColor Red }; exit 1 }
exit 0
