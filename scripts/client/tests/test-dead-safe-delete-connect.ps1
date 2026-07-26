# test-dead-safe-delete-connect.ps1 - SAFE_DELETE helpers must stay gone (0 product defs)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== Dead SAFE_DELETE helpers ===" -ForegroundColor Cyan
Write-Host ""

$checks = @(
    @{ File = 'windows\connect.ps1'; Names = @('Escape-BashSingleQuoted', 'Get-ActiveMountId') }
    @{ File = 'editor-launch.ps1'; Names = @('Start-EditorProcessQuiet', 'Stop-CursorServerProfileTreeIfNeeded') }
    @{ File = 'connect-ui.ps1'; Names = @('Write-ConnectPhaseLog', 'Write-ConnectTimedLog', 'Invoke-ConnectPerfBlock') }
    @{ File = 'git-mode.ps1'; Names = @('Unmount-OtherProjects', 'Test-TunnelPortOccupiedByPeer') }
)

foreach ($c in $checks) {
    $path = Get-ClientFile $c.File
    $src = Get-Content -LiteralPath $path -Raw
    foreach ($name in $c.Names) {
        Assert ($src -notmatch ("function\s+{0}\b" -f [regex]::Escape($name))) "$($c.File) has no function $name"
    }
}

# KEEP_BUT_WIRE — must NOT be deleted by this slice
$ui = Get-Content -LiteralPath (Get-ClientFile 'connect-ui.ps1') -Raw
Assert ($ui -match 'function\s+Write-ConnectUserFacingError\b') 'KEEP Write-ConnectUserFacingError still defined'

$el = Get-Content -LiteralPath (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($el -match 'function\s+Start-EditorProcessDirect\b') 'Start-EditorProcessDirect remains (Quiet replacement)'
Assert ($el -notmatch 'function\s+Start-EditorProcessQuiet\b') 'Start-EditorProcessQuiet definition removed'

Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1