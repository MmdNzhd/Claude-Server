$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'scripts\client\tests\_paths.ps1')
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; exit 1 }
}
foreach ($rel in @('windows\connect.ps1')) {
    $path = Get-ClientFile $rel
    $src = Get-Content $path -Raw
    Assert ($src -notmatch '[\u201C\u201D\u2018\u2019]') "$rel has no smart/curly quotes (PS 5.1 break)"
}
# Extra: connect-ui / git-mode also clean under default encoding
foreach ($rel in @('connect-ui.ps1','git-mode.ps1','windows\connect-update.ps1')) {
    $path = Get-ClientFile $rel
    $src = Get-Content $path -Raw
    $ok = $src -notmatch '[\u201C\u201D\u2018\u2019\u2013\u2014]'
    Assert $ok "$rel has no curly/emdash under default Get-Content"
}
Write-Host 'ALL_ASSERTS_OK'
