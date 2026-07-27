#Requires -Version 5.1
# test-harder-live-versioned-prune.ps1
#
# HARDER LIVE (~14 asserts) for setup-launch versioned helpers + update prune parity.
# Extracts REAL functions from publish\_setup-launch-body.ps1 (+ Invoke-PruneConnectVersionDirs).
# Adversarial vs test-versioned-layout-extra-hard-batch.ps1:
#   - Deeper spaced roots (nested "outer spaced\inner drop")
#   - Move-LaunchExeIntoVerDir copy-over fallback when DestExe already exists
#   - Prune exactly 4 cross-date VerDirs with keep=3 (oldest removed)
#   - Wrong-version Test-VersionSrcComplete edges on hostile src mutations
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: versioned tree + prune (spaced adversarial) ===' -ForegroundColor White
Write-Host ''

$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$updPath = Get-ClientFile 'windows\connect-update.ps1'
$launchSrc = Get-Content -LiteralPath $launchPath -Raw
$updSrc = Get-Content -LiteralPath $updPath -Raw

$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$testVer = '20991231.42'
$pubExe = Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)
if (-not (Test-Path -LiteralPath $pubExe)) {
    $pubExe = Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe'
}
if (-not (Test-Path -LiteralPath $pubExe)) {
    $pubExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
}
if (-not (Test-Path -LiteralPath $pubExe)) {
    Write-Host '  FAIL  no seed Claude-Connect.exe for live move tests' -ForegroundColor Red
    exit 1
}
$seedHash = (Get-FileHash -LiteralPath $pubExe -Algorithm MD5).Hash

# ---------------------------------------------------------------------------
# Extract REAL setup-launch helpers (+ update prune for parity)
# ---------------------------------------------------------------------------
Note 'extract setup-launch + update prune helpers'
$needLaunch = @(
    'Resolve-VersionedTree',
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

# Nested spaced root — adversarial path class
$root = Join-Path $env:TEMP ("cc harder prune " + [guid]::NewGuid().ToString('N').Substring(0, 8))
$spacedDrop = Join-Path $root 'outer spaced\inner drop'
$extract = Join-Path $root 'IXP000.TMP'
$null = New-Item -ItemType Directory -Force -Path $spacedDrop, $extract

try {
    $winSrc = Join-Path $script:RepoRoot 'scripts\client\windows'
    foreach ($rel in @('connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1', 'connect-version.txt')) {
        $from = Join-Path $winSrc $rel
        if (Test-Path $from) { Copy-Item $from (Join-Path $extract $rel) -Force }
    }
    Set-Content -LiteralPath (Join-Path $extract 'connect-version.txt') -Value $testVer -Encoding ASCII -NoNewline

    # 1-3: Resolve-VersionedTree — Root/VerDir/SrcDir/DestExe under nested spaced path
    Note 'Resolve-VersionedTree nested spaced parents'
    $tDrop = Resolve-VersionedTree -LaunchParent $spacedDrop -Version $testVer
    $verDirPath = $tDrop.VerDir
    $srcDirPath = $tDrop.SrcDir
    $null = New-Item -ItemType Directory -Force -Path $srcDirPath
    $tFromVer = Resolve-VersionedTree -LaunchParent $verDirPath -Version $testVer
    $tFromSrc = Resolve-VersionedTree -LaunchParent $srcDirPath -Version $testVer

    $expectRoot = [IO.Path]::GetFullPath((Join-Path $spacedDrop 'Claude-Connect'))
    $expectVer = [IO.Path]::GetFullPath((Join-Path $expectRoot $testVer))
    $expectSrc = [IO.Path]::GetFullPath((Join-Path $expectVer 'src'))
    $expectDest = [IO.Path]::GetFullPath((Join-Path $expectVer ("Claude-Connect-{0}.exe" -f $testVer)))

    Assert (
        ($tDrop.Root -eq $expectRoot) -and
        ($tDrop.VerDir -eq $expectVer) -and
        ($tDrop.SrcDir -eq $expectSrc) -and
        ($tDrop.DestExe -eq $expectDest)
    ) 'Resolve-VersionedTree spaced drop yields Root/VerDir/SrcDir/DestExe tree'

    Assert (
        ($tFromVer.Root -eq $tDrop.Root) -and
        ($tFromVer.DestExe -eq $tDrop.DestExe) -and
        ($tFromVer.SrcDir -eq $tDrop.SrcDir)
    ) 'Resolve-VersionedTree from inside {ver} agrees with drop parent'

    Assert (
        ($tFromSrc.Root -eq $tDrop.Root) -and
        ($tFromSrc.VerDir -eq $verDirPath) -and
        ($tFromSrc.DestExe -eq $tDrop.DestExe)
    ) 'Resolve-VersionedTree from inside src agrees with drop parent'

    # 4-5: Move-LaunchExeIntoVerDir — fresh move into VerDir; drop must be clean
    Note 'Move-LaunchExeIntoVerDir fresh move'
    $launchExe = Join-Path $spacedDrop ("Claude-Connect-{0}.exe" -f $testVer)
    Copy-Item -LiteralPath $pubExe -Destination $launchExe -Force
    $moved = Move-LaunchExeIntoVerDir -LaunchExe $launchExe -DestExe $tDrop.DestExe `
        -LaunchParent $spacedDrop -VerDir $verDirPath
    Assert (
        $moved -and (Test-Path -LiteralPath $tDrop.DestExe) -and (-not (Test-Path -LiteralPath $launchExe))
    ) 'Move-LaunchExeIntoVerDir moved EXE into VerDir; none left in spaced drop'

    $dropExes = @(Get-ChildItem -LiteralPath $spacedDrop -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert ($dropExes.Count -eq 0) 'no Claude-Connect*.exe remains anywhere under nested spaced drop'

    # 6-7: install batch — payload into src, current.txt pointer, no EXE leak
    Note 'install batch: src payload + current.txt + no EXE in src'
    Copy-PayloadToSrc -ExtractSrc $extract -SrcDir $srcDirPath
    Set-Content -LiteralPath (Join-Path $tDrop.Root 'current.txt') -Value $testVer -Encoding ASCII -NoNewline
    $srcExes = @(Get-ChildItem -LiteralPath $srcDirPath -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert ($srcExes.Count -eq 0) 'no EXE inside src\ after payload copy batch'
    Assert ((Get-Content (Join-Path $tDrop.Root 'current.txt') -Raw).Trim() -eq $testVer) `
        'current.txt pointer matches installed version under spaced tree'

    # 8: adversarial copy-over fallback when DestExe already exists (move-fail path)
    Note 'Move-LaunchExeIntoVerDir copy-over fallback when DestExe pre-exists'
    $staleDest = $tDrop.DestExe
    $staleBytes = [IO.File]::ReadAllBytes($staleDest)
    if ($staleBytes.Length -gt 48) { $staleBytes[24] = ($staleBytes[24] -bxor 0xA5) }
    [IO.File]::WriteAllBytes($staleDest, $staleBytes)
    $launchExe2 = Join-Path $spacedDrop ("Claude-Connect-{0}.exe" -f $testVer)
    Copy-Item -LiteralPath $pubExe -Destination $launchExe2 -Force
    $copied = Move-LaunchExeIntoVerDir -LaunchExe $launchExe2 -DestExe $staleDest `
        -LaunchParent $spacedDrop -VerDir $verDirPath
    Assert (
        $copied -and
        ((Get-FileHash -LiteralPath $staleDest -Algorithm MD5).Hash -eq $seedHash) -and
        (-not (Test-Path -LiteralPath $launchExe2))
    ) 'Move-LaunchExeIntoVerDir copy-over fallback refreshes pre-existing DestExe and clears drop'

    # 9-12: Test-VersionSrcComplete — match + wrong-version adversarial edges
    Note 'Test-VersionSrcComplete wrong version edges'
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
        'Test-VersionSrcComplete false when connect-update.ps1 missing from src'

    # 12-14: prune exactly 4 cross-date VerDirs keep=3 + update parity
    Note 'prune keep=3 on exactly 4 cross-date VerDirs'
    $pruneRoot = Join-Path $root 'prune four spaced'
    New-Item -ItemType Directory -Force -Path $pruneRoot | Out-Null
    $fourVers = @('20260110.1', '20260220.2', '20260330.3', '20260425.4')
    foreach ($v in $fourVers) {
        $d = Join-Path $pruneRoot $v
        New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
    }
    Prune-OldVersionDirs -Root $pruneRoot -Keep 3
    $leftSetup = @(Get-ChildItem $pruneRoot -Directory | Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object { $_.Name } | Sort-Object)
    Assert (
        ($leftSetup.Count -eq 3) -and
        ($leftSetup -notcontains '20260110.1') -and
        ($leftSetup -contains '20260425.4') -and
        ($leftSetup -contains '20260330.3') -and
        ($leftSetup -contains '20260220.2')
    ) 'Prune-OldVersionDirs keep=3 on 4 VerDirs drops oldest; retains newest trio'

    Remove-Item -LiteralPath $pruneRoot -Recurse -Force
    New-Item -ItemType Directory -Force -Path $pruneRoot | Out-Null
    foreach ($v in $fourVers) {
        $d = Join-Path $pruneRoot $v
        New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
    }
    Invoke-PruneConnectVersionDirs -Root $pruneRoot -Keep 3
    $leftUpd = @(Get-ChildItem $pruneRoot -Directory | Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object { $_.Name } | Sort-Object)
    Assert (($leftUpd -join ',') -eq ($leftSetup -join ',')) `
        'Invoke-PruneConnectVersionDirs parity with setup prune on same 4-version tree'

} catch {
    Write-Host ("  FAIL  harder live prune exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARD LIVE PRUNE RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Green
    exit 0
}
Write-Host ("HARD LIVE PRUNE RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
exit 1
