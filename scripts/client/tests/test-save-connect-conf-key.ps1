#Requires -Version 5.1
# Task 5: sticky REMOTE_USER — username save preserves other conf keys
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Save-ConnectConfKey contracts ===' -ForegroundColor White
$win = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($win -match 'function Save-ConnectConfKey') 'Save-ConnectConfKey helper exists'
Assert ($win -notmatch '@\("REMOTE_USER=\$') 'no two-key REMOTE_USER Set-Content wipe'

$tmp = Join-Path $env:TEMP ("claude-connect-conf-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$cfg = Join-Path $tmp 'connect.conf'
@"
REMOTE_USER=testsmart
LAPTOP_USER=Smart
GIT_MODE=off
TUNNEL_SLOT=1
PORT=20021
"@ | Set-Content -Path $cfg -Encoding ASCII

$m = [regex]::Match($win, '(?ms)^function\s+Save-ConnectConfKey\b.*?(?=^function\s+|\z)')
Assert ($m.Success) 'extracted Save-ConnectConfKey'
if ($m.Success) {
    $fnFile = Join-Path $tmp 'helper.ps1'
    # trim trailing content after closing brace of function
    $body = $m.Value
    $end = $body.IndexOf("`n}")
    if ($end -lt 0) { $end = $body.IndexOf("`r`n}") }
    # Use balanced extract: first line function ... until line that is only }
    $lines = $body -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $depth = 0
    foreach ($line in $lines) {
        $out.Add($line) | Out-Null
        $depth += ([regex]::Matches($line, '\{')).Count
        $depth -= ([regex]::Matches($line, '\}')).Count
        if ($depth -le 0 -and $out.Count -gt 1) { break }
    }
    ($out -join "`n") | Set-Content -Path $fnFile -Encoding UTF8
    . $fnFile
    Save-ConnectConfKey -Path $cfg -Key 'REMOTE_USER' -Value 'smart'
    $map = @{}
    Get-Content $cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $map[$Matches[1]] = $Matches[2] } }
    Assert ($map['REMOTE_USER'] -eq 'smart') 'REMOTE_USER updated to smart'
    Assert ($map['LAPTOP_USER'] -eq 'Smart') 'LAPTOP_USER preserved'
    Assert ($map['GIT_MODE'] -eq 'off') 'GIT_MODE preserved'
    Assert ($map['TUNNEL_SLOT'] -eq '1') 'TUNNEL_SLOT preserved'
    Assert ($map['PORT'] -eq '20021') 'PORT preserved'
}
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host ''
if ($failed -gt 0) { Write-Host "FAIL save-connect-conf-key ($failed failed)" -ForegroundColor Red; exit 1 }
Write-Host "PASS save-connect-conf-key ($passed checks)" -ForegroundColor Green
exit 0
