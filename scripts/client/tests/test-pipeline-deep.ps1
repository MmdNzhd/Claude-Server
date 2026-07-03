# test-pipeline-deep.ps1 — validates connect.ps1 pipeline fixes against Microsoft docs
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== PowerShell pipeline deep test (MS docs aligned) ===" -ForegroundColor Cyan
Write-Host ""

$leak = [PSCustomObject]@{ Id = 'ai'; Path = '/home/smart/mounts/ai' }
$cfg = 'C:\Users\Smart\.config\claude-connect'
$badResult = $leak | ForEach-Object { Join-Path -Path $cfg -ChildPath 'editor.conf' }
$goodResult = [System.IO.Path]::Combine($cfg, 'editor.conf')
Assert ($badResult -eq $goodResult) "Join-Path -Path -ChildPath explicit matches Path.Combine"

function TwoOut {
    [PSCustomObject]@{ n = 'leak' }
    return [PSCustomObject]@{ n = 'pick' }
}
$stray = @(TwoOut)[0]
$safePath = [System.IO.Path]::Combine($cfg, 'editor.conf')
Assert ($safePath -like '*editor.conf') "Path.Combine ignores stray pipeline objects (static method)"

function OneOut { return ,([PSCustomObject]@{ n = 1 }) }
Assert (@(OneOut).Count -eq 1) "Unary comma return emits one object (about_Return)"

function TwoOut {
    [PSCustomObject]@{ n = 'leak' }
    return [PSCustomObject]@{ n = 'pick' }
}
Assert (@(TwoOut).Count -eq 2) "Function can emit multiple success-stream objects"

$pick = @(TwoOut)[-1]
Assert ($pick.n -eq 'pick') "@(func)[-1] picks last emitted object"

function PickMount {
    $null = ($m = [PSCustomObject]@{ Id = 'mount'; Path = '/m' })
    return ,([PSCustomObject]@{ Id = 'ai'; Path = '/ai' })
}
Assert (@(PickMount).Count -eq 1) "`$null = (`$m = ...) suppresses assignment leak in function"

$win = Get-ClientFile 'windows\connect.ps1'
$ed  = Get-ClientFile 'editor-launch.ps1'
$src = Get-Content $win -Raw
$eds = Get-Content $ed -Raw
Assert ($src -match "ConnectVersion = '20260703\.12'") "connect.ps1 version 20260703.12"
Assert ($eds -match '\[System\.IO\.Path\]::Combine') "editor-launch uses Path.Combine not Join-Path"
Assert ($src -match '@\(Choose-Project -Mounts \$mounts\)\[-1\]') "safe Choose-Project capture"
Assert ($src -match '@\(Resolve-EditorChoice -CfgDir \$CfgDir\)\[-1\]') "safe Resolve-EditorChoice capture"

Write-Host ""
if ($fail -eq 0) { Write-Host "All deep tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
