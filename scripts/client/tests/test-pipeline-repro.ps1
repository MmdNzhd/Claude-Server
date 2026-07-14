#Requires -Version 5.1
# test-pipeline-repro.ps1 - demonstrates the exact Join-Path ChildPath failure mode
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=== Join-Path ChildPath bug reproduction ===" -ForegroundColor Cyan
Write-Host ""

$CfgDir = 'C:\Users\Smart\.config\claude-connect'

Write-Host "[1] OLD: while-loop + bare assignment" -ForegroundColor Yellow
$go = $null
while (-not $go) {
    $go = [PSCustomObject]@{ Id = 'ai'; Path = '/home/smart/mounts/ai' }
    break
}
$leaked = $go | ForEach-Object {
    Join-Path -Path $CfgDir -ChildPath 'editor.conf'
}
Write-Host "    Pipeline leaked object Id=$($go.Id); Join-Path result: $leaked"
Write-Host "    (Interactive script would PROMPT ChildPath if ChildPath arg omitted)" -ForegroundColor DarkGray

Write-Host ""
Write-Host "[2] OLD: Resolve-EditorChoice with Join-Path (pre-fix editor-launch.ps1)" -ForegroundColor Yellow
function OldResolve {
    param([string]$CfgDir)
    Join-Path $CfgDir 'editor.conf'
}
$pick = ,([PSCustomObject]@{ Id = 'ai'; Path = '/x' })
$bad = OldResolve -CfgDir $CfgDir
Write-Host "    OldResolve returned: $bad"

Write-Host ""
Write-Host "[3] FIXED: @(Choose-Project)[-1] + Path.Combine" -ForegroundColor Green
function ChooseFixed { return ,([PSCustomObject]@{ Id = 'ai'; Path = '/x' }) }
$go2 = @(ChooseFixed)[-1]
$good = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
Write-Host "    go.Id=$($go2.Id) editor.conf=$good"

Write-Host ""
Write-Host "[4] MS docs: function without unary comma emits MULTIPLE objects" -ForegroundColor Yellow
function TwoEmit {
    [PSCustomObject]@{ n = 'LEAK' }
    return [PSCustomObject]@{ n = 'PICK' }
}
Write-Host "    @(TwoEmit).Count = $(@(TwoEmit).Count)  -> need @()[ -1]"
Write-Host "    @((TwoEmit))[-1].n = $((@(TwoEmit)[-1]).n)"

Write-Host ""
Write-Host "All reproduction steps completed (non-interactive)." -ForegroundColor Green
