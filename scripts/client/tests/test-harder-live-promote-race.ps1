#Requires -Version 5.1
# test-harder-live-promote-race.ps1
#
# HARD LIVE (~14 asserts): concurrent Sync-ConnectExeBesideClient against the SAME
# external launch dir + SAME last-launch-dir stamp (promote race), plus versioned
# VerDir foreign_verdir guard (no Claude-Connect-NEW.exe into OLD/mid VerDir).
# Extracts REAL helpers from connect-update.ps1 via Get-FunctionSource.
# Does NOT touch production scripts or run-all.ps1.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: promote race + VerDir foreign leak ===' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Seed EXE (Desktop\Claude-Connect or claude-publish)
# ---------------------------------------------------------------------------
$live = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$liveExe = Join-Path $live 'Claude-Connect.exe'
if (-not (Test-Path -LiteralPath $liveExe)) {
    $ver = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
    $pubCandidates = @(
        (Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $ver)),
        (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
    )
    foreach ($c in $pubCandidates) {
        if (Test-Path -LiteralPath $c) {
            if (-not (Test-Path -LiteralPath $live)) {
                New-Item -ItemType Directory -Force -Path $live | Out-Null
            }
            Copy-Item -LiteralPath $c -Destination $liveExe -Force
            Note ("seeded live EXE from {0}" -f $c)
            break
        }
    }
}
Assert (Test-Path -LiteralPath $liveExe) 'seed Claude-Connect.exe from Desktop or claude-publish'
$srcHash = if (Test-Path -LiteralPath $liveExe) {
    (Get-FileHash -LiteralPath $liveExe -Algorithm MD5).Hash
} else { $null }

# ---------------------------------------------------------------------------
# Extract REAL helpers from connect-update.ps1
# ---------------------------------------------------------------------------
Note 'extract real Sync/Promote helpers from connect-update.ps1'
$updPath = Get-ClientFile 'windows\connect-update.ps1'
$updSrc = Get-Content -LiteralPath $updPath -Raw
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
[void]$chunk.AppendLine('Set-StrictMode -Version Latest')
[void]$chunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.99'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        if ($n -eq 'Test-ConnectLaunchDirUsable') {
            [void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param([string]$Dir) if(-not $Dir){return $false}; try { $full=[IO.Path]::GetFullPath($Dir) } catch { return $false }; if($full -match ''(?i)(?:^|[\\/])(?:WindowsPowerShell|System32|SysWOW64)(?:[\\/]|$)''){return $false}; return $true }')
            continue
        }
        Assert $false "extract $n from connect-update.ps1"
        throw "missing function $n"
    }
    [void]$chunk.AppendLine($fn)
    [void]$chunk.AppendLine('')
}
$chunkText = $chunk.ToString()
$chunkText = $chunkText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$script:TestPromoteStamp'
$chunkText = $chunkText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'
Assert ($chunkText -match '\$script:TestPromoteStamp') 'extracted helpers use isolated TestPromoteStamp'

$syncFn = Get-FunctionSource -Content $updSrc -Name 'Sync-ConnectExeBesideClient'
Assert (
    $syncFn -and ($syncFn -match 'foreign_verdir') -and ($syncFn -match 'if \(\$dirLeaf -ne \$verLabel\)')
) 'Sync-ConnectExeBesideClient ships foreign_verdir guard'

$root = Join-Path $env:TEMP ("cc-promote-race-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$sharedLaunch = Join-Path $root 'shared-launch'
$sharedInstall = Join-Path $root 'install'
$sharedStamp = Join-Path $root 'last-launch-dir.txt'
$null = New-Item -ItemType Directory -Force -Path $sharedLaunch, $sharedInstall
Copy-Item -LiteralPath $liveExe -Destination (Join-Path $sharedInstall 'Claude-Connect.exe') -Force
Set-Content -LiteralPath $sharedStamp -Value $sharedLaunch -Encoding ASCII -NoNewline

# Decoy older EXE — must survive concurrent promote storm
$decoy = Join-Path $sharedLaunch 'Claude-Connect-20990101.00.exe'
Copy-Item -LiteralPath $liveExe -Destination $decoy -Force
$decoyHash = (Get-FileHash -LiteralPath $decoy -Algorithm MD5).Hash

try {
    # -----------------------------------------------------------------------
    # Case 1: 4 parallel workers, SAME stamp + SAME external launch dir
    # -----------------------------------------------------------------------
    Note 'Case1: 4 concurrent Sync workers -> one shared launch dir + stamp'
    $labels = @('20990101.01', '20990101.02', '20990101.03', '20990101.04')
    $jobs = @()
    foreach ($lab in $labels) {
        $jobs += Start-Job -ScriptBlock {
            param($Chunk, $Stamp, $Launch, $Install, $Label, $SrcHash)
            $ErrorActionPreference = 'Stop'
            $script:TestPromoteStamp = $Stamp
            $ScriptDir = $Install
            Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
            Remove-Item Env:CLAUDE_CONNECT_VER_DIR -ErrorAction SilentlyContinue
            Remove-Item Env:CLAUDE_CONNECT_ROOT -ErrorAction SilentlyContinue
            Invoke-Expression $Chunk
            Sync-ConnectExeBesideClient -VersionLabel $Label
            $dest = Join-Path $Launch ("Claude-Connect-{0}.exe" -f $Label)
            $ok = (Test-Path -LiteralPath $dest) -and ((Get-FileHash -LiteralPath $dest -Algorithm MD5).Hash -eq $SrcHash)
            [pscustomobject]@{ Label = $Label; Ok = [bool]$ok; Path = $dest }
        } -ArgumentList $chunkText, $sharedStamp, $sharedLaunch, $sharedInstall, $lab, $srcHash
    }
    $raceResults = @($jobs | Wait-Job -Timeout 120 | Receive-Job)
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue

    $raceOk = @($raceResults | Where-Object { $_.Ok }).Count
    Assert ($raceOk -eq 4) ("Case1 concurrent promote 4/4 ok (got $raceOk)")

    $missing = @($labels | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $sharedLaunch ("Claude-Connect-{0}.exe" -f $_)))
        })
    Assert ($missing.Count -eq 0) ("Case1 all 4 versioned EXEs in shared launch (missing: $($missing -join ','))")

    $badMd5 = @($labels | Where-Object {
            $p = Join-Path $sharedLaunch ("Claude-Connect-{0}.exe" -f $_)
            (Test-Path -LiteralPath $p) -and ((Get-FileHash -LiteralPath $p -Algorithm MD5).Hash -ne $srcHash)
        })
    Assert ($badMd5.Count -eq 0) ("Case1 all 4 promoted EXEs md5 match seed (bad: $($badMd5 -join ','))")

    Assert (
        (Test-Path -LiteralPath $decoy) -and
        ((Get-FileHash -LiteralPath $decoy -Algorithm MD5).Hash -eq $decoyHash)
    ) 'Case1 decoy older EXE kept with unchanged hash'

    $tmpDebris = @(Get-ChildItem -LiteralPath $sharedLaunch -Filter '*.old-*' -File -ErrorAction SilentlyContinue)
    Assert ($tmpDebris.Count -eq 0) ("Case1 no .old-* tmp debris in shared launch (found $($tmpDebris.Count))")

    # Load helpers in main runspace for Cases 2–3
    $script:TestPromoteStamp = $sharedStamp
    $ScriptDir = $sharedInstall
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Invoke-Expression $chunkText

    # -----------------------------------------------------------------------
    # Case 2: versioned tree — stamp=OLD VerDir, Sync NEW label
    # -----------------------------------------------------------------------
    Note 'Case2: stamp=OLD VerDir, Sync NEW — no NEW.exe leak into OLD'
    $appRoot = Join-Path $root 'Claude-Connect'
    $oldVer = '20990101.10'
    $newVer = '20990101.20'
    $oldVerDir = Join-Path $appRoot $oldVer
    $newVerDir = Join-Path $appRoot $newVer
    $oldSrc = Join-Path $oldVerDir 'src'
    $newSrc = Join-Path $newVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $oldSrc, $newSrc
    Set-Content -LiteralPath (Join-Path $oldSrc 'connect.ps1') -Value '# stub' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $newSrc 'connect.ps1') -Value '# stub' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $appRoot 'current.txt') -Value $newVer -Encoding ASCII -NoNewline
    Copy-Item -LiteralPath $liveExe -Destination (Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $oldVer)) -Force
    Copy-Item -LiteralPath $liveExe -Destination (Join-Path $newVerDir ("Claude-Connect-{0}.exe" -f $newVer)) -Force

    $ScriptDir = $newSrc
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    $env:CLAUDE_CONNECT_ROOT = $appRoot
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $sharedStamp -Value $oldVerDir -Encoding ASCII -NoNewline

    Sync-ConnectExeBesideClient -VersionLabel $newVer

    $leakOld = Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $newVer)
    Assert (-not (Test-Path -LiteralPath $leakOld)) 'Case2 no Claude-Connect-NEW.exe leak into OLD VerDir'

    $oldExes = @(Get-ChildItem -LiteralPath $oldVerDir -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert (
        ($oldExes.Count -eq 1) -and ($oldExes[0].Name -eq ("Claude-Connect-{0}.exe" -f $oldVer))
    ) ("Case2 OLD VerDir exactly 1 matching EXE (got $($oldExes.Count))")

    $newExes = @(Get-ChildItem -LiteralPath $newVerDir -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert (
        ($newExes.Count -eq 1) -and
        ($newExes[0].Name -eq ("Claude-Connect-{0}.exe" -f $newVer)) -and
        ((Get-FileHash -LiteralPath $newExes[0].FullName -Algorithm MD5).Hash -eq $srcHash)
    ) ("Case2 NEW VerDir exactly 1 matching EXE with ok md5 (got $($newExes.Count))")

    # -----------------------------------------------------------------------
    # Case 3: pre-planted corrupted foreign leak in mid VerDir — hash must stay
    # -----------------------------------------------------------------------
    Note 'Case3: corrupted foreign leak in mid VerDir — Sync must not refresh'
    $midVer = '20990101.15'
    $midVerDir = Join-Path $appRoot $midVer
    $midSrc = Join-Path $midVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $midSrc
    Set-Content -LiteralPath (Join-Path $midSrc 'connect.ps1') -Value '# stub' -Encoding ASCII

    $foreignLeak = Join-Path $midVerDir ("Claude-Connect-{0}.exe" -f $newVer)
    [IO.File]::WriteAllBytes($foreignLeak, [byte[]](1..127))
    $corruptHash = (Get-FileHash -LiteralPath $foreignLeak -Algorithm MD5).Hash
    Assert ($corruptHash -ne $srcHash) 'Case3 pre-planted foreign leak has corrupt hash (not seed)'

    # Stamp lists mid VerDir so promoteDirs includes it; foreign_verdir must skip refresh.
    Set-Content -LiteralPath $sharedStamp -Value $midVerDir -Encoding ASCII -NoNewline
    $ScriptDir = $newSrc
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    Sync-ConnectExeBesideClient -VersionLabel $newVer

    $afterHash = (Get-FileHash -LiteralPath $foreignLeak -Algorithm MD5).Hash
    Assert (
        (Test-Path -LiteralPath $foreignLeak) -and ($afterHash -eq $corruptHash)
    ) 'Case3 Sync left corrupted foreign leak hash unchanged'

    $midExes = @(Get-ChildItem -LiteralPath $midVerDir -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    Assert ($midExes.Count -eq 1) ("Case3 mid VerDir still exactly 1 EXE (got $($midExes.Count))")

} catch {
    Write-Host ("  FAIL  sandbox exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_VER_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_ROOT -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
Write-Host ("PATH:  {0}" -f $updPath) -ForegroundColor DarkGray
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
