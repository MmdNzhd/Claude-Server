#Requires -Version 5.1
# Stage 1b: SSH remote bash payloads must strip CR before send (fix $'do\r').

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}
function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Stage 1b: SSH remote bash LF-only ===' -ForegroundColor White
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$git = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$core = Get-FunctionSource $win 'Invoke-SshXCore'
$open = Get-FunctionSource $git 'Get-ServerOpenTunnelPorts'
Assert ($core.Length -gt 50) 'Invoke-SshXCore extracted'
Assert ($core -match 'replace\s+"`r`n"|replace\s+''`r`n''|-replace\s+"`r`n"') 'Invoke-SshXCore strips CR LF'
Assert ($core -match '-replace\s+"`r"') 'Invoke-SshXCore strips lone CR'
# Sanitizer must run before Base64 encode
$idxReplace = $core.IndexOf('-replace')
$idxB64 = $core.IndexOf('ToBase64String')
Assert ($idxReplace -ge 0 -and $idxB64 -gt $idxReplace) 'CR strip happens before ToBase64String'
Assert ($open -match 'for p in') 'Get-ServerOpenTunnelPorts still has for-loop probe'
Assert ($open -match '-replace\s+"`r|ConvertTo-Lf|Sanitize') 'Get-ServerOpenTunnelPorts also LF-normalizes script (defense)'

# Unit: simulate sanitizer contract
$sample = "for p in 20026 20027; do`r`n  echo OPEN:`$p`r`ndone`r`n"
$san = ($sample -replace "`r`n", "`n") -replace "`r", "`n"
Assert ($san -notmatch "`r") 'sample sanitizer removes all CR'
Assert ($san -match 'for p in 20026 20027; do\n') 'sample keeps LF newlines'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
