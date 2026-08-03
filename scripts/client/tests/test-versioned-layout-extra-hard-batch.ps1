#Requires -Version 5.1
# test-versioned-layout-extra-hard-batch.ps1
#
# Extra-hard batch (~14 live asserts) for setup-launch versioned helpers.
# Uses REAL extracted functions from publish\_setup-launch-body.ps1 (+ update prune parity).
# Deliberately avoids cases already covered by sibling test-versioned-layout*.ps1:
#   - Sync foreign_verdir / promote thrash (hard-regressions, harder-adversarial)
#   - orphan cmd / triple rapid launch (hard-regressions, harder-adversarial)
#   - first-install timing / server parity / flat migrate (deep-live)
#   - basic prune 20260101.{1,5,12,15} (test-versioned-layout, deep-live)
#
# Focus: Resolve-VersionedTree shapes, DestExe naming, Move-LaunchExeIntoVerDir,
# current.txt pointer, no EXE in src\ or Claude-Connect root, Test-VersionSrcComplete
# wrong-version edges, cross-date prune keep=3 live extract.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== EXTRA-HARD BATCH: versioned layout (setup-launch live) ===' -ForegroundColor White
Write-Host ''

$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$updPath = Get-ClientFile 'windows\connect-update.ps1'
$launchSrc = Get-Content -LiteralPath $launchPath -Raw
$updSrc = Get-Content -LiteralPath $updPath -Raw

$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$testVer = '20991231.7'
$pubExe = Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)
if (-not (Test-Path -LiteralPath $pubExe)) {
    $pubExe = Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe'
}
if (-not (Test-Path -LiteralPath $pubExe)) {
    $pubExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
}
if (-not (Test-Path -LiteralPath $pubExe)) {
    Write-Host '  FAIL  no seed Claude-Connect.exe for move tests' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Extract REAL setup-launch helpers (+ update prune for parity)
# ---------------------------------------------------------------------------
Note 'extract setup-launch + update prune helpers'
$needLaunch = @(
    'Resolve-VersionedTree',
    'Test-VersionSrcStructural',
    'Get-ConnectPs1EmbeddedVersionLocal',
    'Set-SrcVersionStamp',
    'Test-VersionSrcComplete',
    'Copy-PayloadToSrc',
    'Move-LaunchExeIntoVerDir',
    'Prune-OldVersionDirs'
)
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$chunk.AppendLine('function Log([string]$m) { }')
foreach ($n in $needLaunch) {
    $fn = Get-FunctionSource -Content $launchSrc -Name $n
    if (-not $fn) { Assert $false "extract $n"; throw "missing $n" }
    [void]$chunk.AppendLine($fn)
}
$pruneUpd = Get-FunctionSource -Content $updSrc -Name 'Invoke-PruneConnectVersionDirs'
if (-not $pruneUpd) { Assert $false 'extract Invoke-PruneConnectVersionDirs'; throw 'missing prune' }
$uchunk = New-Object System.Text.StringBuilder
[void]$uchunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$uchunk.AppendLine($pruneUpd)

Invoke-Expression $chunk.ToString()
Invoke-Expression $uchunk.ToString()

# Spaced root — "test for update" class path (not Resolve-VersionedTree-tested in siblings)
$root = Join-Path $env:TEMP ("test for update cc-extra-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$spacedDrop = Join-Path $root 'drop folder'
$extract = Join-Path $root 'IXP000.TMP'
$null = New-Item -ItemType Directory -Force -Path $spacedDrop, $extract

try {
    # Test seam: redirect install-current pointer at an isolated file under this test's
    # temp root so this test NEVER touches the real live
    # %USERPROFILE%\.config\claude-connect\install-current.txt (hit live 2026-08-03).
    $savedInstallCurrentOverride = $env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH
    $env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH = Join-Path $root 'install-current.txt'
    . (Get-ClientFile 'windows\connect-env-repair.ps1')

    $winSrc = Join-Path $script:RepoRoot 'scripts\client\windows'
    foreach ($rel in @(
        'connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1',
        'connect-version.txt', 'connect-env-repair.ps1'
    )) {
        $from = Join-Path $winSrc $rel
        if (Test-Path $from) { Copy-Item $from (Join-Path $extract $rel) -Force }
    }
    $clientRoot = Join-Path $script:RepoRoot 'scripts\client'
    foreach ($rel in @('editor-launch.ps1', 'connect-ui.ps1')) {
        $from = Join-Path $clientRoot $rel
        if (Test-Path $from) { Copy-Item $from (Join-Path $extract $rel) -Force }
        else { Set-Content -LiteralPath (Join-Path $extract $rel) -Value 'x' }
    }
    Set-Content -LiteralPath (Join-Path $extract 'connect-version.txt') -Value $testVer -Encoding ASCII -NoNewline

    # 1-3: Resolve-VersionedTree under spaced path + nested launch-parent shapes
    Note 'Resolve-VersionedTree spaced + nested parents'
    $tDrop = Resolve-VersionedTree -LaunchParent $spacedDrop -Version $testVer
    $verDirPath = $tDrop.VerDir
    $srcDirPath = $tDrop.SrcDir
    $null = New-Item -ItemType Directory -Force -Path $srcDirPath
    $tFromVer = Resolve-VersionedTree -LaunchParent $verDirPath -Version $testVer
    $tFromSrc = Resolve-VersionedTree -LaunchParent $srcDirPath -Version $testVer

    Assert (
        ($tDrop.Root -eq ([IO.Path]::GetFullPath((Join-Path $spacedDrop 'Claude-Connect')))) -and
        ($tDrop.SrcDir -match '[\\/]src$') -and
        ($tFromVer.DestExe -eq $tDrop.DestExe) -and
        ($tFromSrc.VerDir -eq $verDirPath)
    ) 'Resolve-VersionedTree spaced drop + inside-{ver} + src parents agree on tree'

    # 4: DestExe naming
    $destLeaf = Split-Path -Leaf $tDrop.DestExe
    Assert (
        ($destLeaf -eq ("Claude-Connect-{0}.exe" -f $testVer)) -and
        ($destLeaf -ne 'Claude-Connect.exe')
    ) 'DestExe is Claude-Connect-{ver}.exe not bare name'

    # 5-6: Move-LaunchExeIntoVerDir live move + idempotent
    Note 'Move-LaunchExeIntoVerDir'
    $launchExe = Join-Path $spacedDrop ("Claude-Connect-{0}.exe" -f $testVer)
    Copy-Item -LiteralPath $pubExe -Destination $launchExe -Force
    $moved = Move-LaunchExeIntoVerDir -LaunchExe $launchExe -DestExe $tDrop.DestExe `
        -LaunchParent $spacedDrop -VerDir $verDirPath
    $again = Move-LaunchExeIntoVerDir -LaunchExe $tDrop.DestExe -DestExe $tDrop.DestExe `
        -LaunchParent $spacedDrop -VerDir $verDirPath
    Assert (
        $moved -and (Test-Path -LiteralPath $tDrop.DestExe) -and (-not (Test-Path -LiteralPath $launchExe))
    ) 'Move-LaunchExeIntoVerDir moved EXE into VerDir and removed drop copy'
    Assert (-not $again) 'Move-LaunchExeIntoVerDir idempotent when src already equals DestExe'

    # 7-9: install batch — folders-only root + no EXE leak
    Note 'install batch: folders-only root + no EXE in src or root'
    Copy-PayloadToSrc -ExtractSrc $extract -SrcDir $srcDirPath
    # Align embedded ConnectVersion with testVer (real connect.ps1 has live repo ver).
    $ps1Path = Join-Path $srcDirPath 'connect.ps1'
    $ps1Raw = Get-Content -LiteralPath $ps1Path -Raw -ErrorAction Stop
    $ps1Aligned = [regex]::Replace($ps1Raw, "(?m)(ConnectVersion\s*=\s*)'[^']+'", "`$1'$testVer'")
    [IO.File]::WriteAllText($ps1Path, $ps1Aligned, [Text.UTF8Encoding]::new($false))
    Set-Content -LiteralPath (Join-Path $srcDirPath 'connect-version.txt') -Value $testVer -Encoding ASCII -NoNewline
    Remove-Item -LiteralPath (Join-Path $tDrop.Root 'current.txt') -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Get-ConnectInstallCurrentPath) -Value $testVer -Encoding ASCII -NoNewline
    Assert (-not (Test-Path -LiteralPath (Join-Path $tDrop.Root 'current.txt'))) `
        'no root current.txt (pointer is install-current.txt)'
    Assert (((Get-Content (Get-ConnectInstallCurrentPath) -Raw).Trim()) -eq $testVer) `
        'install-current pointer matches installed version'
    $srcExes = @(Get-ChildItem -LiteralPath $srcDirPath -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert ($srcExes.Count -eq 0) 'no EXE inside src\ after payload + move batch'
    $rootExes = @(Get-ChildItem -LiteralPath $tDrop.Root -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert ($rootExes.Count -eq 0) 'no EXE at Claude-Connect root after install batch'
    $dropExes = @(Get-ChildItem -LiteralPath $spacedDrop -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert ($dropExes.Count -eq 0) 'no EXE left in spaced launch-parent drop after move'

    # 10-13: Test-VersionSrcComplete wrong-version edges
    Note 'Test-VersionSrcComplete wrong version'
    Assert (Test-VersionSrcComplete -SrcDir $srcDirPath -Version $testVer) `
        'Test-VersionSrcComplete true when src complete and version matches'
    Assert (-not (Test-VersionSrcComplete -SrcDir $srcDirPath -Version '20991231.99')) `
        'Test-VersionSrcComplete false for wrong Version arg'
    Set-Content -LiteralPath (Join-Path $srcDirPath 'connect-version.txt') -Value '20991231.99' -Encoding ASCII -NoNewline
    Assert (-not (Test-VersionSrcComplete -SrcDir $srcDirPath -Version $testVer)) `
        'Test-VersionSrcComplete false when connect-version.txt mismatches arg'
    Set-Content -LiteralPath (Join-Path $srcDirPath 'connect-version.txt') -Value $testVer -Encoding ASCII -NoNewline
    Remove-Item -LiteralPath (Join-Path $srcDirPath 'connect-update.ps1') -Force
    Assert (-not (Test-VersionSrcComplete -SrcDir $srcDirPath -Version $testVer)) `
        'Test-VersionSrcComplete false when connect-update.ps1 missing'

    # 14-15: cross-date prune keep=3 live extract + update parity
    Note 'prune keep=3 cross-date live extract'
    $pruneRoot = Join-Path $root 'prune cross-date'
    New-Item -ItemType Directory -Force -Path $pruneRoot | Out-Null
    foreach ($v in @('20260115.1', '20260201.1', '20260201.5', '20260301.1', '20260301.2')) {
        $d = Join-Path $pruneRoot $v
        New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
    }
    Prune-OldVersionDirs -Root $pruneRoot -Keep 3
    $leftSetup = @(Get-ChildItem $pruneRoot -Directory | Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object { $_.Name } | Sort-Object)
    Assert (
        ($leftSetup.Count -eq 3) -and
        ($leftSetup -contains '20260301.2') -and
        ($leftSetup -contains '20260301.1') -and
        ($leftSetup -contains '20260201.5') -and
        ($leftSetup -notcontains '20260115.1')
    ) 'Prune-OldVersionDirs keep=3 retains newest cross-date trio'

    Remove-Item -LiteralPath $pruneRoot -Recurse -Force
    New-Item -ItemType Directory -Force -Path $pruneRoot | Out-Null
    foreach ($v in @('20260115.1', '20260201.1', '20260201.5', '20260301.1', '20260301.2')) {
        $d = Join-Path $pruneRoot $v
        New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
    }
    Invoke-PruneConnectVersionDirs -Root $pruneRoot -Keep 3
    $leftUpd = @(Get-ChildItem $pruneRoot -Directory | Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object { $_.Name } | Sort-Object)
    Assert (($leftUpd -join ',') -eq ($leftSetup -join ',')) `
        'Invoke-PruneConnectVersionDirs parity with setup prune on same tree'

} catch {
    Write-Host ("  FAIL  extra-hard batch exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    # Test-seam-only cleanup: this test never wrote to the real live install-current.txt
    # (all writes were redirected via CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH above), so
    # there is nothing to restore on the live pointer - just release the override.
    if ($null -eq $savedInstallCurrentOverride) {
        Remove-Item Env:\CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH -ErrorAction SilentlyContinue
    } else {
        $env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH = $savedInstallCurrentOverride
    }
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("EXTRA-HARD BATCH RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Green
    exit 0
}
Write-Host ("EXTRA-HARD BATCH RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
exit 1
