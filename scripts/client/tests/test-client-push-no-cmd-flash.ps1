# test-client-push-no-cmd-flash.ps1 - fleet push must not spam visible cmd.exe on Windows laptops
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
function Assert([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw "ASSERT FAIL: $Msg" }
    Write-Host "  PASS  $Msg" -ForegroundColor Green
}
$push = Join-Path $script:ScriptsRoot 'server\claude-client-push-laptop.sh'
Assert (Test-Path -LiteralPath $push) 'claude-client-push-laptop.sh exists'
$src = Get-Content -LiteralPath $push -Raw
Assert ($src -match 'ssh_l_ps_hidden') 'uses hidden EncodedCommand helper'
Assert ($src -match 'IDLE_STAMP_SECS') 'has idle stamp'
Assert ($src -match 'WindowStyle Hidden') 'WindowStyle Hidden on Windows probe'
Assert ($src -notmatch 'cmd /c if exist') 'no cmd /c if exist version probe'
Assert ($src -notmatch 'cmd /c echo %USERPROFILE%') 'no cmd /c Desktop echo fallback as primary'
Assert ($src -match 'Already current') 'skips Connect.bat rewrite when current'
Write-Host 'OK test-client-push-no-cmd-flash' -ForegroundColor Green
