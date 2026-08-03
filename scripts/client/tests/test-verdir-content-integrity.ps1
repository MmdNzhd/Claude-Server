#Requires -Version 5.1
# Regression: folder name must match connect.ps1 ConnectVersion (2026-08-03 poison).
# Run: powershell -NoProfile -File scripts\client\tests\test-verdir-content-integrity.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here '_paths.ps1')

$repair = Get-ClientFile 'windows\connect-env-repair.ps1'
. $repair

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "PASS $msg" -ForegroundColor Green }
    else { Write-Host "FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path $env:TEMP ("cc-verdir-integrity-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$verDir = Join-Path $root 'Claude-Connect\20260803.99'
$src = Join-Path $verDir 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null

# Minimal required files; ps1 claims OLDER version than folder.
@('connect-boot.ps1', 'connect-update.ps1', 'connect.bat') | ForEach-Object {
    Set-Content -LiteralPath (Join-Path $src $_) -Value "# stub $_" -Encoding ASCII
}
Set-Content -LiteralPath (Join-Path $src 'connect.ps1') -Value @"
# poison fixture
`$script:ConnectVersion = '20260803.01'
"@ -Encoding ASCII
# Pretend someone (old Repair) stamped folder name onto txt while ps1 disagrees.
Set-Content -LiteralPath (Join-Path $src 'connect-version.txt') -Value '20260803.99' -Encoding ASCII -NoNewline

Assert (-not (Test-ConnectVerSrcComplete -SrcDir $src -Ver '20260803.99')) `
    'poisoned tree (txt=folder, ps1 older) is NOT complete'

[void](Repair-ConnectVerDirLayout -VerDir $verDir -Quiet)
$txtAfter = (Get-Content -LiteralPath (Join-Path $src 'connect-version.txt') -Raw).Trim()
Assert ($txtAfter -eq '20260803.01') 'Repair keeps txt honest to connect.ps1 (not folder lie)'
Assert (-not (Test-ConnectVerSrcComplete -SrcDir $src -Ver '20260803.99')) `
    'after Repair, folder/ps1 mismatch still incomplete'

# Healthy: all three agree
Set-Content -LiteralPath (Join-Path $src 'connect.ps1') -Value @"
`$script:ConnectVersion = '20260803.99'
"@ -Encoding ASCII
Set-Content -LiteralPath (Join-Path $src 'connect-version.txt') -Value '20260803.99' -Encoding ASCII -NoNewline
Assert (Test-ConnectVerSrcComplete -SrcDir $src -Ver '20260803.99') 'healthy matching tree is complete'
[void](Repair-ConnectVerDirLayout -VerDir $verDir -Quiet)
Assert (((Get-Content (Join-Path $src 'connect-version.txt') -Raw).Trim()) -eq '20260803.99') `
    'Repair may re-stamp txt when ps1 matches folder'

# install-current must reject poison pointer (isolated root — no leftover .99 fixture)
$appRoot2 = Join-Path $env:TEMP ("cc-verdir-ptr-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '\Claude-Connect')
$badSrc = Join-Path $appRoot2 '20260803.88\src'
New-Item -ItemType Directory -Force -Path $badSrc | Out-Null
@('connect-boot.ps1', 'connect-update.ps1', 'connect.bat') | ForEach-Object {
    Set-Content -LiteralPath (Join-Path $badSrc $_) -Value '#x' -Encoding ASCII
}
Set-Content -LiteralPath (Join-Path $badSrc 'connect.ps1') -Value "`$script:ConnectVersion = '20260803.01'" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $badSrc 'connect-version.txt') -Value '20260803.88' -Encoding ASCII -NoNewline
# Good sibling
$goodSrc = Join-Path $appRoot2 '20260803.77\src'
New-Item -ItemType Directory -Force -Path $goodSrc | Out-Null
@('connect-boot.ps1', 'connect-update.ps1', 'connect.bat') | ForEach-Object {
    Set-Content -LiteralPath (Join-Path $goodSrc $_) -Value '#x' -Encoding ASCII
}
Set-Content -LiteralPath (Join-Path $goodSrc 'connect.ps1') -Value "`$script:ConnectVersion = '20260803.77'" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $goodSrc 'connect-version.txt') -Value '20260803.77' -Encoding ASCII -NoNewline

# Test seam: redirect Get-ConnectInstallCurrentPath at an isolated temp file via
# CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH so this test NEVER touches the real live
# %USERPROFILE%\.config\claude-connect\install-current.txt (hit live 2026-08-03: test
# wrote 20260803.88 into the real pointer).
$savedOverride = $env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH
$testPtrFile = Join-Path $env:TEMP ("cc-verdir-ptr-file-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
try {
    $env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH = $testPtrFile
    $ptrPath = Get-ConnectInstallCurrentPath
    Assert ($ptrPath -eq $testPtrFile) `
        'Get-ConnectInstallCurrentPath respects CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH override'

    Set-Content -LiteralPath $ptrPath -Value '20260803.88' -Encoding ASCII -NoNewline
    $resolved = Get-ConnectInstallCurrent -Root $appRoot2
    Assert ($resolved -eq '20260803.77') 'install-current skips poisoned .88 and picks healthy .77'
} finally {
    if ($null -eq $savedOverride) {
        Remove-Item Env:\CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH -ErrorAction SilentlyContinue
    } else {
        $env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH = $savedOverride
    }
    Remove-Item -LiteralPath $testPtrFile -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Split-Path $appRoot2 -Parent) -Recurse -Force -ErrorAction SilentlyContinue
if ($fail -gt 0) { Write-Host "FAILED $fail"; exit 1 }
Write-Host 'ALL PASS'
exit 0
