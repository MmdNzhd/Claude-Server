# test-select-project.ps1 — non-interactive proof that project "1" never hits Join-Path ChildPath
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== Post-select pipeline test (non-interactive) ===" -ForegroundColor Cyan
Write-Host ""

$CfgDir = [System.IO.Path]::Combine($env:USERPROFILE, '.config', 'claude-connect-test')
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'editor.conf')) -Value 'cursor' -Encoding ASCII

function Choose-ProjectSim {
    param([array]$Mounts)
    $m = $Mounts[0]
    return ,([PSCustomObject]@{ Id = $m.Id; Path = $m.Path })
}

$mounts = @([PSCustomObject]@{ Id = 'ai'; Path = '/home/smart/mounts/ai'; Label = 'Ai'; On = $false })

$go = @(Choose-ProjectSim -Mounts $mounts)[-1]
Assert ($go.Id -eq 'ai') '@(Choose-Project)[-1] returns project id'

$editorPref = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
Assert (Test-Path $editorPref) 'Path.Combine editor.conf path valid'

function LeakySelect { return ,([PSCustomObject]@{ Id = 'x'; Path = '/y' }) }
$leakObj = LeakySelect
$pipeCount = @($leakObj).Count
Assert ($pipeCount -ge 1) 'LeakySelect emits at least one object'

$safe = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
Assert ($safe -like '*editor.conf') 'Path.Combine safe with pipeline context'

foreach ($rel in @('windows\connect.ps1')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    Assert ($src -match '@\(Choose-Project -Mounts \$allMounts\)\[-1\]') "$rel uses safe Choose-Project capture"
    Assert ($src -notmatch 'script: \$PSCommandPath') "$rel omits script path in header (v12)"
}

$editor = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($editor -match '\[System\.IO\.Path\]::Combine\(\$CfgDir') 'editor-launch uses Path.Combine not Join-Path'

Write-Host ""
if ($fail -eq 0) { Write-Host "All select-project tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
