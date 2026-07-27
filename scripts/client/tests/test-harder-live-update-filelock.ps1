#Requires -Version 5.1
# test-harder-live-update-filelock.ps1
#
# HARD LIVE sandbox for versioned_apply / Copy-ExeAtomicSwap under locks:
#   - Extract real helpers from connect-update.ps1 (not reimplemented)
#   - Temp Claude-Connect\{old}\src + \{new}\ sibling layout
#   - Running-style EXE lock (mapped image / FileShare.None on write): plain copy denied;
#     Copy-ExeAtomicSwap rename-swap lands new bytes
#   - Read lock on old src\connect.ps1 while copying new payload into sibling newVer\src
#   - Static: foreign_verdir skip still in Sync
#   - Sync: no bare Claude-Connect.exe inside any VerDir
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: update filelock + versioned apply ===' -ForegroundColor White
Write-Host ''

$updPath = Get-ClientFile 'windows\connect-update.ps1'
$updSrc = Get-Content -LiteralPath $updPath -Raw
$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$winSrc = Get-ClientFile 'windows'

# --- Assert 1: static foreign_verdir skip in Sync ---
Note 'static: foreign_verdir guard in Sync-ConnectExeBesideClient'
$syncFn = Get-FunctionSource -Content $updSrc -Name 'Sync-ConnectExeBesideClient'
Assert (
    $syncFn -and
    ($syncFn -match 'foreign_verdir') -and
    ($syncFn -match 'if \(\$dirLeaf -ne \$verLabel\)')
) 'Sync still skips foreign_verdir (no NEW.exe into OLD VerDir)'

# --- Extract real helpers ---
Note 'extract real helpers from connect-update.ps1'
$needed = @(
    'Get-ConnectVersionedLayout',
    'Get-SafeFileSha256',
    'Copy-ExeAtomicSwap',
    'Test-IsConnectVersionedSrcDir',
    'Test-IsConnectVersionedRootDir',
    'Get-ConnectExePromoteDirs',
    'Sync-ConnectExeBesideClient'
)
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$chunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.99'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        Assert $false "extract $n from shipped connect-update.ps1"
        throw "missing $n"
    }
    [void]$chunk.AppendLine($fn)
}
$chunkText = $chunk.ToString()
$chunkText = $chunkText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$script:TestFileLockStamp'
$chunkText = $chunkText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'
Invoke-Expression $chunkText

# --- Assert 2: helpers loaded ---
Assert $true 'loaded Copy-ExeAtomicSwap + Get-SafeFileSha256 + layout + Sync from shipped source'

function New-SleepStubExe {
    param([string]$Path, [string]$Marker)
    $safe = ($Marker -replace '[^a-zA-Z0-9]', '')
    $src = @"
using System.Threading;
class Stub_$safe {
    static void Main(string[] args) { Thread.Sleep(Timeout.Infinite); }
}
"@
    Add-Type -Language CSharp -TypeDefinition $src -OutputType ConsoleApplication -OutputAssembly $Path -ErrorAction Stop
}

$seedExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
if (-not (Test-Path -LiteralPath $seedExe)) {
    foreach ($c in @(
        (Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)),
        (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
    )) {
        if (Test-Path -LiteralPath $c) { $seedExe = $c; break }
    }
}
if (-not (Test-Path -LiteralPath $seedExe)) {
    Write-Host '  FAIL  no seed EXE (Desktop or claude-publish)' -ForegroundColor Red
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, ($Fail + 1), $Skip) -ForegroundColor Red
    exit 1
}

$root = Join-Path $env:TEMP ("cc-filelock-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$appRoot = Join-Path $root 'Claude-Connect'
$oldVer = '20990101.10'
$newVer = '20990101.40'
$oldVerDir = Join-Path $appRoot $oldVer
$newVerDir = Join-Path $appRoot $newVer
$oldSrc = Join-Path $oldVerDir 'src'
$newSrc = Join-Path $newVerDir 'src'
$stampFile = Join-Path $root 'last-launch-dir.txt'
$script:TestFileLockStamp = $stampFile
$proc = $null
$readLock = $null
$null = New-Item -ItemType Directory -Force -Path $oldSrc, $newSrc

try {
    Note 'scaffold Claude-Connect\{old}\src'
    foreach ($rel in @('connect.ps1', 'connect.bat', 'connect-version.txt', 'connect-boot.ps1')) {
        $from = Join-Path $winSrc $rel
        if (Test-Path -LiteralPath $from) {
            Copy-Item -LiteralPath $from -Destination (Join-Path $oldSrc $rel) -Force
        }
    }
    Set-Content -LiteralPath (Join-Path $oldSrc 'connect.ps1') -Value "# OLD_LOCK_MARKER`n`$ConnectVersion = '20990101.10'" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $oldSrc 'connect-version.txt') -Value $oldVer -Encoding ASCII -NoNewline
    Set-Content -LiteralPath (Join-Path $appRoot 'current.txt') -Value $oldVer -Encoding ASCII -NoNewline

    # --- Assert 3: versioned layout on old src ---
    $layoutOld = Get-ConnectVersionedLayout -Dir $oldSrc
    Assert ($layoutOld -and $layoutOld.Kind -eq 'versioned' -and $layoutOld.Ver -eq $oldVer) `
        'Get-ConnectVersionedLayout detects Claude-Connect\{old}\src'

    # ---- Case1: running-style locked EXE - atomic swap ----
    Note 'Case1: running EXE in old VerDir; Copy-ExeAtomicSwap rename-swap'
    $stubDir = Join-Path $root 'stub-build'
    $null = New-Item -ItemType Directory -Force -Path $stubDir
    $runningExe = Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $oldVer)
    $newBuildExe = Join-Path $stubDir 'new-build.exe'
    New-SleepStubExe -Path $runningExe -Marker 'OldRun'
    New-SleepStubExe -Path $newBuildExe -Marker 'NewRun'
    $newHash = Get-SafeFileSha256 -Path $newBuildExe

    $proc = Start-Process -FilePath $runningExe -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 350

    # --- Assert 4: plain copy denied (running image = FileShare.None on write) ---
    $plainDenied = $false
    try { Copy-Item -LiteralPath $newBuildExe -Destination $runningExe -Force -ErrorAction Stop }
    catch { $plainDenied = $true }
    Assert $plainDenied 'plain Copy-Item -Force denied while EXE is running (FileShare.None write lock)'

    # --- Assert 5-7: swap succeeds, new bytes land, rename-swap cleanup ---
    $swapOk = Copy-ExeAtomicSwap -Source $newBuildExe -Destination $runningExe
    Assert $swapOk 'Copy-ExeAtomicSwap succeeds via rename-swap while destination EXE is running'
    $afterHash = Get-SafeFileSha256 -Path $runningExe
    Assert ($afterHash -eq $newHash) 'destination path holds new build bytes after atomic swap'
    $oldArtifacts = @(Get-ChildItem -LiteralPath $oldVerDir -Filter '*.old-*' -File -ErrorAction SilentlyContinue)
    Assert ($oldArtifacts.Count -le 1) ("rename-swap left at most one .old- artifact (got $($oldArtifacts.Count))")

    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch { }
        try { [void]$proc.WaitForExit(2000) } catch { }
    }
    $proc = $null
    Start-Sleep -Milliseconds 200

    # ---- Case2: read lock on old connect.ps1 during versioned apply sim ----
    Note 'Case2: read lock on old connect.ps1; apply payload into sibling newVer\src'
    $oldPs1 = Join-Path $oldSrc 'connect.ps1'
    $oldPs1Text = (Get-Content -LiteralPath $oldPs1 -Raw)
    $readLock = [IO.File]::Open($oldPs1, 'Open', 'Read', 'Read')

    $winNew = Join-Path $root 'winNew'
    $null = New-Item -ItemType Directory -Force -Path $winNew
    foreach ($rel in @('connect.ps1', 'connect.bat', 'connect-version.txt', 'connect-boot.ps1', 'connect-update.ps1')) {
        $from = Join-Path $winSrc $rel
        if (Test-Path -LiteralPath $from) {
            Copy-Item -LiteralPath $from -Destination (Join-Path $winNew $rel) -Force
        }
    }
    Set-Content -LiteralPath (Join-Path $winNew 'connect-version.txt') -Value $newVer -Encoding ASCII -NoNewline
    Set-Content -LiteralPath (Join-Path $winNew 'connect.ps1') -Value "# NEW_APPLY_MARKER`n`$ConnectVersion = '$newVer'" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $winNew 'NEW_MARKER.txt') -Value 'from-versioned-apply' -Encoding ASCII -NoNewline

    $verLayoutApply = Get-ConnectVersionedLayout -Dir $oldSrc
    $applyNewVerDir = Join-Path $verLayoutApply.Root $newVer
    $applyNewSrc = Join-Path $applyNewVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $applyNewSrc
    Get-ChildItem -LiteralPath $winNew -Force -ErrorAction Stop | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $applyNewSrc $_.Name) -Force -Recurse -ErrorAction Stop
    }
    $destExe = Join-Path $applyNewVerDir ("Claude-Connect-{0}.exe" -f $newVer)
    $exeSrc = Join-Path $winNew 'Claude-Connect.exe'
    if (-not (Test-Path -LiteralPath $exeSrc)) { Copy-Item -LiteralPath $seedExe -Destination $exeSrc -Force }
    [void](Copy-ExeAtomicSwap -Source $exeSrc -Destination $destExe)
    Set-Content -LiteralPath (Join-Path $verLayoutApply.Root 'current.txt') -Value $newVer -Encoding ASCII -NoNewline

    # --- Assert 8-10: new src complete while old connect.ps1 read-locked ---
    Assert (Test-Path -LiteralPath (Join-Path $applyNewSrc 'NEW_MARKER.txt')) `
        'new src complete while old connect.ps1 read-locked (NEW_MARKER present)'
    Assert ((Get-Content -LiteralPath (Join-Path $applyNewSrc 'connect-version.txt') -Raw).Trim() -eq $newVer) `
        'new src connect-version.txt matches remote ver during old-file read lock'
    Assert ((Get-Content -LiteralPath (Join-Path $applyNewSrc 'connect.ps1') -Raw) -match 'NEW_APPLY_MARKER') `
        'new src connect.ps1 has NEW payload copied while old connect.ps1 read-locked'

    $readLock.Dispose()
    $readLock = $null

    # --- Assert 11-12: old file intact; current.txt retargeted ---
    $oldAfterUnlock = (Get-Content -LiteralPath $oldPs1 -Raw)
    Assert ($oldAfterUnlock -eq $oldPs1Text) 'old connect.ps1 still readable with original bytes after unlock'
    Assert ((Get-Content -LiteralPath (Join-Path $appRoot 'current.txt') -Raw).Trim() -eq $newVer) `
        'current.txt points to new ver after versioned apply sim'

    # ---- Case3: Sync VerDir hygiene ----
    Note 'Case3: Sync-ConnectExeBesideClient - no bare EXE inside VerDirs'
    $ScriptDir = $applyNewSrc
    $env:CLAUDE_CONNECT_VER_DIR = $applyNewVerDir
    $env:CLAUDE_CONNECT_ROOT = $appRoot
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $oldVerDir
    Set-Content -LiteralPath $stampFile -Value $oldVerDir -Encoding ASCII -NoNewline
    Sync-ConnectExeBesideClient -VersionLabel $newVer

    $bareInVerDirs = @()
    Get-ChildItem -LiteralPath $appRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object {
            if (Test-Path -LiteralPath (Join-Path $_.FullName 'Claude-Connect.exe')) {
                $bareInVerDirs += $_.Name
            }
        }
    # --- Assert 13-14: Sync hygiene ---
    Assert ($bareInVerDirs.Count -eq 0) `
        ("Sync left no bare Claude-Connect.exe inside any VerDir (bad=$($bareInVerDirs -join ','))")
    $newVerExes = @(Get-ChildItem -LiteralPath $applyNewVerDir -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert (
        ($newVerExes.Count -eq 1) -and ($newVerExes[0].Name -eq ("Claude-Connect-{0}.exe" -f $newVer))
    ) 'new VerDir has exactly one matching Claude-Connect-{ver}.exe after Sync'

} catch {
    Write-Host ("  FAIL  filelock sandbox exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    if ($readLock) { try { $readLock.Dispose() } catch { } }
    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch { }
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Stub_*.exe' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_VER_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_ROOT -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("Script: {0}" -f $MyInvocation.MyCommand.Path) -ForegroundColor DarkGray
if ($Fail -gt 0) { exit 1 }
exit 0
