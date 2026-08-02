#Requires -Version 5.1
# test-versioned-layout-harder-adversarial.ps1
#
# HARDER than test-versioned-layout-hard-regressions.ps1:
#   - Spaced install roots (the "test for update" class)
#   - 4 stacked VerDirs; promote newest while EVERY pointer aims at oldest
#   - Sync SOURCE WinDir = oldest VerDir (hostile) while VersionLabel = newest
#   - Pre-planted foreign leak must not be "refreshed" / enlarged by Sync
#   - External spaced launch folder still receives handoff EXE
#   - Instant launcher under spaces + triple rapid .cmd (orphan cmd = 0)
#   - Global invariant: no VerDir ever holds Claude-Connect-{otherVer}.exe
#
# Uses REAL extracted helpers from connect-update / setup-launch.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

function Get-VerDirExeInventory {
    param([string]$AppRoot)
    $map = @{}
    Get-ChildItem -LiteralPath $AppRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object {
            $exes = @(Get-ChildItem -LiteralPath $_.FullName -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name)
            $map[$_.Name] = $exes
        }
    return $map
}

function Assert-NoForeignExeInAnyVerDir {
    param([string]$AppRoot, [string]$Tag)
    $inv = Get-VerDirExeInventory -AppRoot $AppRoot
    $bad = @()
    foreach ($ver in $inv.Keys) {
        foreach ($name in @($inv[$ver])) {
            if ($name -eq 'Claude-Connect.exe') {
                $bad += "${ver}:bare"
                continue
            }
            if ($name -match '^Claude-Connect-(\d{8}\.\d+)\.exe$') {
                if ($Matches[1] -ne $ver) { $bad += "${ver}:$name" }
            } else {
                $bad += "${ver}:$name"
            }
        }
        if (@($inv[$ver]).Count -ne 1) {
            $bad += ("{0}:count={1}" -f $ver, @($inv[$ver]).Count)
        }
    }
    Assert ($bad.Count -eq 0) ("$Tag global invariant: 1 matching EXE per VerDir (bad=$($bad -join '; '))")
}

Write-Host ''
Write-Host '=== HARDER++: versioned layout adversarial ===' -ForegroundColor White
Write-Host ''

$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$updPath = Get-ClientFile 'windows\connect-update.ps1'
$launchSrc = Get-Content -LiteralPath $launchPath -Raw
$updSrc = Get-Content -LiteralPath $updPath -Raw

$liveExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
if (-not (Test-Path -LiteralPath $liveExe)) {
    foreach ($c in @(
        (Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)),
        (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
    )) {
        if (Test-Path -LiteralPath $c) { $liveExe = $c; break }
    }
}
if (-not (Test-Path -LiteralPath $liveExe)) {
    Write-Host '  FAIL  no seed EXE' -ForegroundColor Red
    exit 1
}
$srcHash = (Get-FileHash -LiteralPath $liveExe -Algorithm MD5).Hash
Note ("seed md5=$srcHash")

# Extract promote helpers (sandbox stamp + no live process scan)
$needed = @(
    'Test-ConnectLaunchDirUsable',
    'Get-ConnectVersionedLayout',
    'Test-IsConnectVersionedSrcDir',
    'Test-IsConnectVersionedRootDir',
    'Get-SafeFileSha256',
    'Copy-ExeAtomicSwap',
    'Get-ConnectExePromoteDirs',
    'Sync-ConnectExeBesideClient'
)
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$chunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.40'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        if ($n -eq 'Test-ConnectLaunchDirUsable') {
            [void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param([string]$Dir) if(-not $Dir){return $false}; try { [void][IO.Path]::GetFullPath($Dir) } catch { return $false }; return $true }')
            continue
        }
        Assert $false "extract $n"; throw "missing $n"
    }
    [void]$chunk.AppendLine($fn)
}
$chunkText = $chunk.ToString()
$chunkText = $chunkText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$script:TestHarderStamp'
$chunkText = $chunkText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'
Assert ($chunkText -match '\$script:TestHarderStamp') 'sandbox stamp rewrite ok'

# Spaced root — reproduces "test for update" class paths
$root = Join-Path $env:TEMP ("cc harder spaced " + [guid]::NewGuid().ToString('N').Substring(0, 8))
$stampFile = Join-Path $root 'last-launch-dir.txt'
$null = New-Item -ItemType Directory -Force -Path $root
$script:TestHarderStamp = $stampFile

try {
    Invoke-Expression $chunkText
    Assert $true 'loaded helpers under spaced sandbox'

    # ---- CaseH1: 4 VerDirs, spaced root, all pointers on oldest, Sync newest ----
    Note 'CaseH1: 4 VerDirs + spaced path + hostile pointers on oldest'
    $drop = Join-Path $root 'drop folder'
    $appRoot = Join-Path $drop 'Claude-Connect'
    $vers = @('20990101.10', '20990101.17', '20990101.20', '20990101.40')
    $newest = $vers[-1]
    $oldest = $vers[0]
    foreach ($v in $vers) {
        $vd = Join-Path $appRoot $v
        $sd = Join-Path $vd 'src'
        $null = New-Item -ItemType Directory -Force -Path $sd
        Set-Content (Join-Path $sd 'connect.ps1') -Value "# $v" -Encoding ASCII
        Set-Content (Join-Path $sd 'connect-boot.ps1') -Value "# boot $v" -Encoding ASCII
        Copy-Item -LiteralPath $liveExe -Destination (Join-Path $vd ("Claude-Connect-{0}.exe" -f $v)) -Force
    }
    Set-Content (Join-Path $appRoot 'current.txt') -Value $newest -Encoding ASCII -NoNewline

    $oldVerDir = Join-Path $appRoot $oldest
    $newVerDir = Join-Path $appRoot $newest
    $newSrc = Join-Path $newVerDir 'src'
    # Pre-plant the EXACT production bug artifact: NEW.exe sitting in OLD .17-style folder
    $mid = '20990101.17'
    $midDir = Join-Path $appRoot $mid
    $preLeak = Join-Path $midDir ("Claude-Connect-{0}.exe" -f $newest)
    Copy-Item -LiteralPath $liveExe -Destination $preLeak -Force
    # Corrupt pre-leak bytes so we can detect any Sync "refresh" of the foreign file
    $leakBytes = [IO.File]::ReadAllBytes($preLeak)
    if ($leakBytes.Length -gt 64) { $leakBytes[32] = ($leakBytes[32] -bxor 0x5A) }
    [IO.File]::WriteAllBytes($preLeak, $leakBytes)
    $preLeakHash = (Get-FileHash -LiteralPath $preLeak -Algorithm MD5).Hash
    Assert (Test-Path $preLeak) 'CaseH1 pre-planted foreign leak in mid VerDir (bug artifact)'

    $ScriptDir = $newSrc
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    $env:CLAUDE_CONNECT_ROOT = $appRoot
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $oldVerDir
    Set-Content -LiteralPath $stampFile -Value $oldVerDir -Encoding ASCII -NoNewline

    # Hostile Sync SOURCE: WinDir resolves from ScriptDir normally; force by also
    # pointing ScriptDir briefly... actually Sync finds exe from versioned layout of ScriptDir.
    # Extra hostile: put stamp on EVERY old ver via sequential Sync with rotating stamps.
    foreach ($v in $vers) {
        if ($v -eq $newest) { continue }
        Set-Content -LiteralPath $stampFile -Value (Join-Path $appRoot $v) -Encoding ASCII -NoNewline
        $env:CLAUDE_CONNECT_LAUNCH_DIR = (Join-Path $appRoot $v)
        Sync-ConnectExeBesideClient -VersionLabel $newest
    }
    # Final hostile burst: stamp+launch on oldest, Sync thrice
    Set-Content -LiteralPath $stampFile -Value $oldVerDir -Encoding ASCII -NoNewline
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $oldVerDir
    1..3 | ForEach-Object { Sync-ConnectExeBesideClient -VersionLabel $newest }

    # Pre-leak must be untouched (skip path must not rewrite foreign file)
    Assert (Test-Path -LiteralPath $preLeak) 'CaseH1 pre-leak file still present (skip does not delete)'
    Assert ((Get-FileHash -LiteralPath $preLeak -Algorithm MD5).Hash -eq $preLeakHash) `
        'CaseH1 Sync did NOT refresh/overwrite pre-planted foreign leak bytes'

    # Newest folder must stay clean single EXE
    $newExes = @(Get-ChildItem -LiteralPath $newVerDir -Filter 'Claude-Connect*.exe' -File)
    Assert ($newExes.Count -eq 1) 'CaseH1 NEW VerDir exactly 1 EXE'
    Assert ($newExes[0].Name -eq ("Claude-Connect-{0}.exe" -f $newest)) 'CaseH1 NEW name matches'

    # Oldest must not gain newest (beyond any pre-plant — oldest had no pre-plant)
    $oldLeak = Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $newest)
    Assert (-not (Test-Path -LiteralPath $oldLeak)) 'CaseH1 oldest did not gain NEW.exe'
    $oldExes = @(Get-ChildItem -LiteralPath $oldVerDir -Filter 'Claude-Connect*.exe' -File)
    Assert ($oldExes.Count -eq 1) 'CaseH1 oldest still exactly 1 EXE'

    # Mid folder already had intentional pre-leak (count=2) — Sync must not add a third
    # or a bare exe, and must not touch leak hash (already checked).
    $midExes = @(Get-ChildItem -LiteralPath $midDir -Filter 'Claude-Connect*.exe' -File)
    Assert ($midExes.Count -eq 2) 'CaseH1 mid VerDir still only own+preleak (no third EXE)'
    Assert (-not (Test-Path (Join-Path $midDir 'Claude-Connect.exe'))) 'CaseH1 mid has no bare EXE'
    Assert (-not (Test-Path (Join-Path $appRoot 'Claude-Connect.exe'))) 'CaseH1 root has no bare EXE'
    Assert (@(Get-ChildItem -LiteralPath $appRoot -Filter 'Claude-Connect*.exe' -File).Count -eq 0) `
        'CaseH1 no versioned EXE litter at Claude-Connect root'

    foreach ($v in @('20990101.10', '20990101.20', '20990101.40')) {
        $vd = Join-Path $appRoot $v
        $foreign = @(Get-ChildItem -LiteralPath $vd -Filter 'Claude-Connect*.exe' -File |
            Where-Object { $_.Name -ne ("Claude-Connect-{0}.exe" -f $v) -and $_.Name -ne 'Claude-Connect.exe' })
        Assert ($foreign.Count -eq 0) ("CaseH1 $v has zero Sync-created foreign EXEs")
    }

    # ---- CaseH2: Sync SOURCE is oldest VerDir EXE, label is newest ----
    Note 'CaseH2: ScriptDir under oldest src; VersionLabel=newest (source confusion)'
    $ScriptDir = Join-Path $oldVerDir 'src'
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $oldVerDir
    Set-Content -LiteralPath $stampFile -Value $oldVerDir -Encoding ASCII -NoNewline
    Sync-ConnectExeBesideClient -VersionLabel $newest
    Assert (-not (Test-Path -LiteralPath $oldLeak)) 'CaseH2 oldest still no NEW.exe after source confusion'
    Assert ((Get-FileHash -LiteralPath $preLeak -Algorithm MD5).Hash -eq $preLeakHash) 'CaseH2 pre-leak hash still intact'

    # ---- CaseH3: external spaced launch folder gets handoff; VerDirs stay policy-clean ----
    Note 'CaseH3: external spaced launch dir handoff'
    $extLaunch = Join-Path $root 'publish handoff'
    $null = New-Item -ItemType Directory -Force -Path $extLaunch
    $ScriptDir = $newSrc
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $extLaunch
    Set-Content -LiteralPath $stampFile -Value $extLaunch -Encoding ASCII -NoNewline
    Sync-ConnectExeBesideClient -VersionLabel $newest
    $extVer = Join-Path $extLaunch ("Claude-Connect-{0}.exe" -f $newest)
    $extBare = Join-Path $extLaunch 'Claude-Connect.exe'
    Assert (Test-Path -LiteralPath $extVer) 'CaseH3 external spaced dir got versioned EXE'
    Assert (Test-Path -LiteralPath $extBare) 'CaseH3 external spaced dir got bare Claude-Connect.exe'
    Assert ((Get-FileHash -LiteralPath $extVer -Algorithm MD5).Hash -eq $srcHash) 'CaseH3 external versioned md5 matches seed'
    Assert (-not (Test-Path -LiteralPath $oldLeak)) 'CaseH3 oldest still clean after external promote'

    # ---- CaseH4: locked matching EXE in NEW VerDir must not break skip for OLD ----
    Note 'CaseH4: lock NEW VerDir EXE; Sync; OLD still clean'
    $lock = $null
    $newOwn = Join-Path $newVerDir ("Claude-Connect-{0}.exe" -f $newest)
    try {
        $lock = [IO.File]::Open($newOwn, 'Open', 'Read', 'None')
        Sync-ConnectExeBesideClient -VersionLabel $newest
        Assert (-not (Test-Path -LiteralPath $oldLeak)) 'CaseH4 oldest clean while NEW EXE locked'
        Assert ((Get-FileHash -LiteralPath $preLeak -Algorithm MD5).Hash -eq $preLeakHash) 'CaseH4 pre-leak untouched while locked'
    } finally {
        if ($lock) { $lock.Dispose() }
    }

} catch {
    Write-Host ("  FAIL  promote harder exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_VER_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_ROOT -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Instant launcher harder: spaced VerDir + triple rapid cmd
# ---------------------------------------------------------------------------
Note 'CaseH5: spaced sandbox Desktop sibling launcher + triple rapid .cmd'
try {
    $lc = New-Object System.Text.StringBuilder
    [void]$lc.AppendLine('function Log([string]$m) { }')
    $wif = Get-FunctionSource -Content $launchSrc -Name 'Write-ConnectInstantLauncher'
    if (-not $wif) { throw 'Write-ConnectInstantLauncher missing' }
    [void]$lc.AppendLine($wif)
    Invoke-Expression $lc.ToString()

    $spaceRoot = Join-Path $root 'space root'
    $instRoot = Join-Path $spaceRoot 'Claude-Connect'
    $instVerDir = Join-Path $instRoot '20990101.30'
    $instSrc = Join-Path $instVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $instSrc
    $marker = Join-Path $spaceRoot 'boot-count.txt'
    Remove-Item $marker -Force -ErrorAction SilentlyContinue
    $boot = @"
`$ErrorActionPreference = 'Stop'
`$f = '$($marker -replace "'", "''")'
`$n = 0
if (Test-Path -LiteralPath `$f) { try { `$n = [int](Get-Content -LiteralPath `$f -Raw).Trim() } catch { `$n = 0 } }
Set-Content -LiteralPath `$f -Value ([string](`$n + 1)) -Encoding ASCII
Start-Sleep -Milliseconds 600
"@
    Set-Content (Join-Path $instSrc 'connect-boot.ps1') -Value $boot -Encoding ASCII
    Write-ConnectInstantLauncher -VerDir $instVerDir -SrcDir $instSrc -Root $instRoot
    $cmd = Join-Path $spaceRoot 'Claude-Connect.cmd'
    $vbs = Join-Path $spaceRoot 'Claude-Connect.vbs'
    Assert ([bool](Test-Path $cmd)) 'CaseH5 cmd beside Claude-Connect (spaced sandbox)'
    Assert ([bool](Test-Path $vbs)) 'CaseH5 vbs beside Claude-Connect (spaced sandbox)'
    Assert (-not (Test-Path (Join-Path $instRoot 'current.txt'))) 'CaseH5 no root current.txt'

    # Triple rapid Explorer-equivalent launches
    1..3 | ForEach-Object {
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @(
            '/d', '/c', "`"$cmd`""
        ) -WorkingDirectory $spaceRoot -WindowStyle Normal | Out-Null
        Start-Sleep -Milliseconds 400
    }

    $deadline = [datetime]::UtcNow.AddSeconds(20)
    $count = 0
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-Path $marker) {
            try { $count = [int](Get-Content $marker -Raw).Trim() } catch { $count = 0 }
            if ($count -ge 3) { break }
        }
        Start-Sleep -Milliseconds 150
    }
    Assert ($count -ge 3) ("CaseH5 triple rapid launch booted >=3 times (got $count)")

    Start-Sleep -Milliseconds 1000
    $orphans = @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        $cl -and ($cl -match [regex]::Escape($cmd))
    })
    Assert ($orphans.Count -eq 0) ("CaseH5 zero orphan cmd after triple launch (got $($orphans.Count))")
    foreach ($o in $orphans) {
        try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }

    # Cleanup boot PS
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($instSrc))
    } | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
} catch {
    Write-Host ("  FAIL  instant harder exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

# ---------------------------------------------------------------------------
# Static harder fail-closed
# ---------------------------------------------------------------------------
Note 'CaseH6: static fail-closed extras'
Assert ($updSrc -match 'foreign_verdir') 'CaseH6 foreign_verdir still present'
Assert ($launchSrc -match 'Claude-Connect\.vbs') 'CaseH6 vbs launcher present'
Assert ($launchSrc -notmatch 'start "Claude Connect" /D') 'CaseH6 no titled start /D'
Assert ($updSrc -match 'Test-IsConnectVersionedRootDir') 'CaseH6 root skip helper present'
Assert ($updSrc -match 'Test-IsConnectVersionedSrcDir') 'CaseH6 src skip helper present'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARDER++ RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("HARDER++ RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
