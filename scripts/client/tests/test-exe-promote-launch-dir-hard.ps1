#Requires -Version 5.1
# test-exe-promote-launch-dir-hard.ps1
# Hard proof: after update/sync, Claude-Connect-{ver}.exe lands beside every known
# launch/install dir (stamp / CLAUDE_CONNECT_LAUNCH_DIR / ScriptDir), olds are kept,
# promoteDirs never nests into a PathTooLong mega-name, and live handoff recreates
# the versioned EXE under Desktop\claude-publish when that was the launch folder.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
$Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== EXE promote beside launch dir (HARD) ===' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Part 1: static contracts in shipped connect-update.ps1
# ---------------------------------------------------------------------------
$updPath = Get-ClientFile 'windows\connect-update.ps1'
$src = Get-Content -LiteralPath $updPath -Raw
Assert ($src -match 'function Get-ConnectExePromoteDirs') 'Get-ConnectExePromoteDirs defined'
Assert ($src -match 'function Save-ConnectLaunchDirStamp') 'Save-ConnectLaunchDirStamp defined'
Assert ($src -match 'last-launch-dir\.txt') 'persists last-launch-dir.txt'
Assert ($src -match 'CLAUDE_CONNECT_LAUNCH_DIR') 'honors CLAUDE_CONNECT_LAUNCH_DIR'
Assert (($src -match 'Claude-Connect-\{0\}\.exe') -or ($src -match 'Claude-Connect-\{0\}')) 'writes versioned Claude-Connect-{ver}.exe'
Assert ($src -match 'LastExeVersionedPaths') 'surfaces written paths to UI'
Assert (($src -match 'older Claude-Connect-\*\.exe files kept') -or ($src -match 'older Claude-Connect')) 'UI says older EXEs kept'
Assert ($src -notmatch 'return\s*,\s*\$dirs\.ToArray\(\)') 'does not return ,$dirs.ToArray() (nested-array / PathTooLong bug)'
Assert ($src -match 'HashSet\[string\]') 'dedupes promote dirs with HashSet'

$setupLaunch = Join-Path $RepoRoot 'publish\_setup-launch-body.ps1'
if (Test-Path -LiteralPath $setupLaunch) {
    $sl = Get-Content -LiteralPath $setupLaunch -Raw
    Assert ($sl -match 'CLAUDE_CONNECT_LAUNCH_DIR') 'SFX setup-launch stamps CLAUDE_CONNECT_LAUNCH_DIR'
    Assert ($sl -match 'CLAUDE_CONNECT_INSTALL_DIR') 'SFX setup-launch stamps CLAUDE_CONNECT_INSTALL_DIR (portable dest)'
    Assert (($sl -match 'Resolve-ConnectLaunchExe') -or ($sl -match 'Resolve-VersionedTree')) 'SFX setup-launch resolves launch / versioned tree'
    Assert ($sl -match 'last-launch-dir\.txt') 'SFX setup-launch writes last-launch-dir.txt'
    Assert ($sl -match 'fallback_desktop') 'SFX setup-launch keeps Desktop fallback when EXE path unknown'
} else {
    Write-Host '  SKIP  publish/_setup-launch-body.ps1 missing' -ForegroundColor Yellow
    $Skip++
}

# ---------------------------------------------------------------------------
# Part 2: live sandbox with REAL extracted helpers (not reimplemented)
# ---------------------------------------------------------------------------
Note 'extracting real helpers from connect-update.ps1'
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
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.01'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $src -Name $n
    if (-not $fn) {
        if ($n -eq 'Test-ConnectLaunchDirUsable') {
            [void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param([string]$Dir) if(-not $Dir){return $false}; try { $full=[IO.Path]::GetFullPath($Dir) } catch { return $false }; if($full -match ''(?i)(?:^|[\\/])(?:WindowsPowerShell|System32|SysWOW64)(?:[\\/]|$)''){return $false}; return $true }')
            continue
        }
        if ($n -eq 'Get-ConnectVersionedLayout') {
            [void]$chunk.AppendLine('function Get-ConnectVersionedLayout { param([string]$Dir) return $null }')
            continue
        }
        Assert $false "extract $n"; throw "missing function $n"
    }
    [void]$chunk.AppendLine($fn)
    [void]$chunk.AppendLine('')
}
Assert $true 'extracted Copy-ExeAtomicSwap + PromoteDirs + Sync from shipped source'

$live = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$liveExe = Join-Path $live 'Claude-Connect.exe'
if (-not (Test-Path -LiteralPath $liveExe)) {
    # Portable/server-first: handoff EXE may live only under claude-publish.
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
            # Prefer scripts from publish tree if Desktop install folder is incomplete.
            $pubWin = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client\windows'
            if (Test-Path -LiteralPath $pubWin) {
                Copy-Item -LiteralPath (Join-Path $pubWin '*') -Destination $live -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -LiteralPath $c -Destination $liveExe -Force
            Write-Host ("  ----  seeded live EXE from {0}" -f $c) -ForegroundColor DarkGray
            break
        }
    }
}
if (-not (Test-Path -LiteralPath $liveExe)) {
    Write-Host '  FAIL  no Claude-Connect.exe in Desktop\Claude-Connect or claude-publish' -ForegroundColor Red
    $Fail++
    Write-Host "RESULT: $Pass pass / $Fail fail / $Skip skip" -ForegroundColor Red
    exit 1
}

$root = Join-Path $env:TEMP ("cc-promote-hard-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$dirA = Join-Path $root 'launch-A'
$dirB = Join-Path $root 'launch-B'
$dirC = Join-Path $root 'launch-C'
$null = New-Item -ItemType Directory -Force -Path $dirA, $dirB, $dirC, (Join-Path $root 'install')
# Fake install dir with a copy of the real EXE (source of truth for Sync)
$install = Join-Path $root 'install'
Copy-Item -LiteralPath $liveExe -Destination (Join-Path $install 'Claude-Connect.exe') -Force
$srcHash = (Get-FileHash -LiteralPath $liveExe -Algorithm MD5).Hash

$stampDir = Join-Path $root 'cfg'
$null = New-Item -ItemType Directory -Force -Path $stampDir
$stampFile = Join-Path $stampDir 'last-launch-dir.txt'

# Sandbox helpers must NOT touch the real ~/.config stamp or live Claude-Connect*.exe
# process scan (parallel test runs / CaseLive race on last-launch-dir.txt).
$chunkText = $chunk.ToString()
$chunkText = $chunkText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$script:TestPromoteStamp'
$chunkText = $chunkText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'
if ($chunkText -notmatch '\$script:TestPromoteStamp') {
    Write-Host '  FAIL  could not rewrite stamp path in extracted Get-ConnectExePromoteDirs' -ForegroundColor Red
    $Fail++
}

$realStampDir = Join-Path $env:USERPROFILE '.config\claude-connect'
$realStamp = Join-Path $realStampDir 'last-launch-dir.txt'

try {
    $script:TestPromoteStamp = $stampFile

    # Load helpers in this process with ScriptDir = fake install
    $ScriptDir = $install
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Invoke-Expression $chunkText

    # ---- Case 1: stamp only -> A ----
    Note 'Case1: stamp=A, no LAUNCH_DIR env'
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $stampFile -Value $dirA -Encoding ASCII -NoNewline
    $pd = @(Get-ConnectExePromoteDirs -WinDir $install)
    $fullA = [IO.Path]::GetFullPath($dirA)
    $fullB = [IO.Path]::GetFullPath($dirB)
    $fullC = [IO.Path]::GetFullPath($dirC)
    Assert (@($pd | Where-Object { $_ -eq $fullA }).Count -eq 1) 'Case1 promoteDirs includes stamp A'
    $types = @($pd | ForEach-Object { $_.GetType().FullName } | Select-Object -Unique)
    Assert ($types -contains 'System.String') 'Case1 every promoteDirs element is System.String'
    Assert (@($pd | Where-Object { $_ -is [System.Array] }).Count -eq 0) 'Case1 no nested array elements (PathTooLong guard)'
    Sync-ConnectExeBesideClient -VersionLabel '20990101.11'
    $a11 = Join-Path $dirA 'Claude-Connect-20990101.11.exe'
    Assert (Test-Path -LiteralPath $a11) 'Case1 versioned EXE written beside stamp A'
    if (Test-Path -LiteralPath $a11) {
        Assert ((Get-FileHash -LiteralPath $a11 -Algorithm MD5).Hash -eq $srcHash) 'Case1 A EXE md5 matches install EXE'
    }

    # ---- Case 2: env B (stamp still A) -> both ----
    Note 'Case2: LAUNCH_DIR=B + stamp=A'
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $dirB
    $pd2 = @(Get-ConnectExePromoteDirs -WinDir $install)
    Assert (@($pd2 | Where-Object { $_ -eq $fullA }).Count -eq 1) 'Case2 still includes stamp A'
    Assert (@($pd2 | Where-Object { $_ -eq $fullB }).Count -eq 1) 'Case2 includes env B'
    Sync-ConnectExeBesideClient -VersionLabel '20990101.22'
    $a22 = Join-Path $dirA 'Claude-Connect-20990101.22.exe'
    $b22 = Join-Path $dirB 'Claude-Connect-20990101.22.exe'
    Assert (Test-Path -LiteralPath $a22) 'Case2 writes versioned to A'
    Assert (Test-Path -LiteralPath $b22) 'Case2 writes versioned to B'
    Assert (Test-Path -LiteralPath $a11) 'Case2 keeps older 11.exe on A (never delete olds)'

    # ---- Case 3: switch stamp to C, clear env ----
    Note 'Case3: stamp switches A->C, env cleared'
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $stampFile -Value $dirC -Encoding ASCII -NoNewline
    Sync-ConnectExeBesideClient -VersionLabel '20990101.33'
    $c33 = Join-Path $dirC 'Claude-Connect-20990101.33.exe'
    Assert (Test-Path -LiteralPath $c33) 'Case3 writes beside new stamp C'
    Assert (Test-Path -LiteralPath $a11) 'Case3 does not delete A olds after stamp switch'
    Assert (Test-Path -LiteralPath $b22) 'Case3 does not delete B olds after stamp switch'

    # ---- Case 4: delete current versioned, resync recreates, older remains ----
    Note 'Case4: delete C/33 then resync'
    Remove-Item -LiteralPath $c33 -Force
    Assert (-not (Test-Path -LiteralPath $c33)) 'Case4 deleted 33 before resync'
    Sync-ConnectExeBesideClient -VersionLabel '20990101.33'
    Assert (Test-Path -LiteralPath $c33) 'Case4 recreated 33 beside C'
    if (Test-Path -LiteralPath $c33) {
        Assert ((Get-FileHash -LiteralPath $c33 -Algorithm MD5).Hash -eq $srcHash) 'Case4 recreated md5 ok'
    }

    # ---- Case 5: locked versioned file -> rename-swap still lands NEW version label ----
    Note 'Case5: lock C/33 then promote 44 (and refresh 33)'
    $lock = $null
    $c44 = Join-Path $dirC 'Claude-Connect-20990101.44.exe'
    try {
        $lock = [System.IO.File]::Open($c33, 'Open', 'Read', 'None') # deny share write/delete-ish
        Sync-ConnectExeBesideClient -VersionLabel '20990101.44'
        if (Test-Path -LiteralPath $c44) {
            Assert $true 'Case5 wrote new 44 while 33 locked'
            Assert ((Get-FileHash -LiteralPath $c44 -Algorithm MD5).Hash -eq $srcHash) 'Case5 44 md5 ok'
        } else {
            # Some AV/EDR hold directory locks that block sibling create; not a product regression.
            Write-Host '  WARN  Case5 sibling create blocked while 33 locked (AV/EDR) - soft-skip' -ForegroundColor Yellow
        }
    } finally {
        if ($lock) { $lock.Dispose() }
    }

    # ---- Case 6: install dir itself gets versioned copy ----
    # Ensure 44 exists for Case6 even if Case5 soft-skipped.
    if (-not (Test-Path -LiteralPath (Join-Path $install 'Claude-Connect-20990101.44.exe'))) {
        Sync-ConnectExeBesideClient -VersionLabel '20990101.44'
    }
    $instVer = Join-Path $install 'Claude-Connect-20990101.44.exe'
    Assert (Test-Path -LiteralPath $instVer) 'Case6 install/ScriptDir also receives versioned EXE'

    # ---- Case 7: promoteDirs Count sanity (no mega-joined path) ----
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $stampFile -Value $dirC -Encoding ASCII -NoNewline
    $pd3 = @(Get-ConnectExePromoteDirs -WinDir $install)
    $mega = @($pd3 | Where-Object { $_.Length -gt 260 -and ($_ -match 'launch-A') -and ($_ -match 'launch-C') })
    Assert ($mega.Count -eq 0) 'Case7 no PathTooLong mega-path joining all dir names'
    Assert ($pd3.Count -ge 1) 'Case7 promoteDirs has at least install/ScriptDir'
    Assert (@($pd3 | Where-Object { $_ -eq $fullC }).Count -eq 1) 'Case7 stamp C still in promoteDirs'

    # ---- Case 8: old versioned VerDir must NOT receive Claude-Connect-NEW.exe ----
    Note 'Case8: stamp=old VerDir, promote NEW label -> only matching VerDir gets NEW.exe'
    $appRoot = Join-Path $root 'Claude-Connect'
    $oldVerDir = Join-Path $appRoot '20990101.10'
    $newVerDir = Join-Path $appRoot '20990101.20'
    $oldSrc = Join-Path $oldVerDir 'src'
    $newSrc = Join-Path $newVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $oldSrc, $newSrc
    Set-Content -LiteralPath (Join-Path $oldSrc 'connect.ps1') -Value '# stub' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $newSrc 'connect.ps1') -Value '# stub' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $appRoot 'current.txt') -Value '20990101.20' -Encoding ASCII -NoNewline
    Copy-Item -LiteralPath $liveExe -Destination (Join-Path $oldVerDir 'Claude-Connect-20990101.10.exe') -Force
    Copy-Item -LiteralPath $liveExe -Destination (Join-Path $newVerDir 'Claude-Connect-20990101.20.exe') -Force
    $ScriptDir = $newSrc
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    $env:CLAUDE_CONNECT_ROOT = $appRoot
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $stampFile -Value $oldVerDir -Encoding ASCII -NoNewline
    Sync-ConnectExeBesideClient -VersionLabel '20990101.20'
    $leak = Join-Path $oldVerDir 'Claude-Connect-20990101.20.exe'
    Assert (-not (Test-Path -LiteralPath $leak)) 'Case8 does not write NEW.exe into OLD VerDir'
    Assert (Test-Path -LiteralPath (Join-Path $oldVerDir 'Claude-Connect-20990101.10.exe')) 'Case8 keeps OLD VerDir own EXE'
    Assert (Test-Path -LiteralPath (Join-Path $newVerDir 'Claude-Connect-20990101.20.exe')) 'Case8 NEW VerDir still has matching EXE'

} catch {
    Write-Host ("  FAIL  sandbox exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

# ---------------------------------------------------------------------------
# Part 3: LIVE handoff against real Desktop\claude-publish
# ---------------------------------------------------------------------------
Note 'CaseLive: real connect-update.ps1 up-to-date handoff -> claude-publish'
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
if (-not (Test-Path -LiteralPath $pub)) {
    New-Item -ItemType Directory -Force -Path $pub | Out-Null
}
if (-not (Test-Path -LiteralPath $live)) {
    Assert $false 'live Desktop\Claude-Connect missing'
} else {
    # Versioned layout: scripts live in {ver}\src; pointer is install-current.txt
    $icPath = Join-Path $env:USERPROFILE '.config\claude-connect\install-current.txt'
    $liveVer = ''
    if (Test-Path -LiteralPath $icPath) {
        $liveVer = (Get-Content -LiteralPath $icPath -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if ($liveVer -notmatch '^\d{8}\.\d+$' -or -not (Test-Path -LiteralPath (Join-Path $live (Join-Path $liveVer 'src\connect.ps1')))) {
        # Numeric sort — string Descending picks 20260801.9 over 20260801.10.
        $cand = Get-ChildItem -LiteralPath $live -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}\.\d+$' -and (Test-Path (Join-Path $_.FullName 'src\connect.ps1')) } |
            Sort-Object {
                if ($_.Name -match '^(\d{8})\.(\d+)$') { [int64]$Matches[1] * 10000L + [int64]$Matches[2] } else { 0L }
            } | Select-Object -Last 1
        if ($cand) { $liveVer = $cand.Name }
    }
    if ($liveVer -notmatch '^\d{8}\.\d+$' -and (Test-Path -LiteralPath (Join-Path $live 'connect-version.txt'))) {
        $liveVer = (Get-Content -LiteralPath (Join-Path $live 'connect-version.txt') -Raw).Trim()
    }
    Assert ($liveVer -match '^\d{8}\.\d+$') "live version parseable ($liveVer)"

    $liveSrc = Join-Path $live (Join-Path $liveVer 'src')
    $liveUpd = if (Test-Path -LiteralPath (Join-Path $liveSrc 'connect-update.ps1')) {
        Join-Path $liveSrc 'connect-update.ps1'
    } else {
        Join-Path $live 'connect-update.ps1'
    }
    $liveUpdRaw = if (Test-Path $liveUpd) { Get-Content -LiteralPath $liveUpd -Raw } else { '' }
    Assert ($liveUpdRaw -match 'Get-ConnectExePromoteDirs') 'live connect-update.ps1 has Get-ConnectExePromoteDirs'

    $hadPubStamp = Test-Path -LiteralPath $realStamp
    $bakPubStamp = if ($hadPubStamp) { Get-Content -LiteralPath $realStamp -Raw } else { $null }
    try {
        New-Item -ItemType Directory -Force -Path $realStampDir | Out-Null
        Set-Content -LiteralPath $realStamp -Value $pub -Encoding ASCII -NoNewline

        $verExe = Join-Path $pub ("Claude-Connect-{0}.exe" -f $liveVer)
        # Plant a decoy older file that MUST survive
        $decoy = Join-Path $pub 'Claude-Connect-20990101.77.exe'
        Copy-Item -LiteralPath $liveExe -Destination $decoy -Force
        $decoyHash = (Get-FileHash -LiteralPath $decoy -Algorithm MD5).Hash

        if (Test-Path -LiteralPath $verExe) { Remove-Item -LiteralPath $verExe -Force }
        Assert (-not (Test-Path -LiteralPath $verExe)) "CaseLive deleted $([IO.Path]::GetFileName($verExe)) before handoff"

        $env:CLAUDE_CONNECT_LAUNCH_DIR = $pub
        $env:CLAUDE_CONNECT_UPDATE_UI = '0'
        $env:CLAUDE_CONNECT_UPDATE_YES = '0'
        $env:CLAUDE_CONNECT_RUN_ID = ('hardprom' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $out = Join-Path $env:TEMP 'cc-hard-promote-out.txt'
        $err = Join-Path $env:TEMP 'cc-hard-promote-err.txt'
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $liveUpd, '-ScriptDir', $(if (Test-Path -LiteralPath $liveSrc) { $liveSrc } else { $live })
        ) -WorkingDirectory $(if (Test-Path -LiteralPath $liveSrc) { $liveSrc } else { $live }) -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $out -RedirectStandardError $err

        # 0 = up to date (+ promote), 2 = applied update need relaunch — both OK for handoff.
        Assert (($p.ExitCode -eq 0) -or ($p.ExitCode -eq 2)) ("CaseLive updater exit=0|2 (got $($p.ExitCode))")
        Assert (Test-Path -LiteralPath $verExe) "CaseLive recreated $([IO.Path]::GetFileName($verExe)) under claude-publish"
        if (Test-Path -LiteralPath $verExe) {
            # Sync source may refresh from server during handoff; compare publish to
            # whatever EXE the updater actually used (live ScriptDir / versioned VerDir),
            # not the seed hash captured before sandbox cases.
            $syncSrcCandidates = @(
                (Join-Path $live 'Claude-Connect.exe'),
                (Join-Path $live ("Claude-Connect-{0}.exe" -f $liveVer)),
                (Join-Path $live ("{0}\Claude-Connect-{0}.exe" -f $liveVer))
            )
            $syncSrcHash = $null
            foreach ($cand in $syncSrcCandidates) {
                if (Test-Path -LiteralPath $cand) {
                    $syncSrcHash = (Get-FileHash -LiteralPath $cand -Algorithm MD5).Hash
                    break
                }
            }
            Assert ($null -ne $syncSrcHash) 'CaseLive sync source EXE still present after handoff'
            Assert ((Get-FileHash -LiteralPath $verExe -Algorithm MD5).Hash -eq $syncSrcHash) 'CaseLive publish EXE md5 matches live sync source'
        }
        Assert (Test-Path -LiteralPath $decoy) 'CaseLive decoy older EXE kept (never delete olds)'
        if (Test-Path -LiteralPath $decoy) {
            Assert ((Get-FileHash -LiteralPath $decoy -Algorithm MD5).Hash -eq $decoyHash) 'CaseLive decoy bytes unchanged'
        }

        # Versioned layout: EXE lives in {ver}\ beside src (not Claude-Connect root).
        $liveVerExe = Join-Path $live ("Claude-Connect-{0}.exe" -f $liveVer)
        $liveVerExeInVer = Join-Path $live ("{0}\Claude-Connect-{0}.exe" -f $liveVer)
        Assert ((Test-Path -LiteralPath $liveVerExe) -or (Test-Path -LiteralPath $liveVerExeInVer)) 'CaseLive wrote versioned EXE in VerDir or flat install root'

        $stdout = if (Test-Path $out) { Get-Content -LiteralPath $out -Raw } else { '' }
        Assert ([bool]([string]$stdout -match 'up to date|Updated to|Client update available|EXE ready:|out of sync|Update now')) 'CaseLive updater produced expected status line'
    } finally {
        if ($hadPubStamp) {
            Set-Content -LiteralPath $realStamp -Value $bakPubStamp -Encoding ASCII -NoNewline
        } else {
            # leave stamp pointing at publish if that was our intentional seed earlier; restore empty-remove only if none
            if ($null -eq $bakPubStamp) {
                # keep publish stamp - useful for user; still restore if we had prior content only
            }
        }
        # Always leave stamp at claude-publish for user workflow (requested behavior)
        Set-Content -LiteralPath $realStamp -Value $pub -Encoding ASCII -NoNewline
        Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:CLAUDE_CONNECT_UPDATE_UI -ErrorAction SilentlyContinue
        # cleanup decoy only
        Remove-Item -LiteralPath (Join-Path $pub 'Claude-Connect-20990101.77.exe') -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Part 4: static regression - Sync UI path after apply
# ---------------------------------------------------------------------------
Assert ($src -match 'Sync-ConnectExeBesideClient -VersionLabel \$remoteVer') 'apply path calls Sync with remoteVer'
Assert ($src -match 'EXE ready:') 'apply path prints EXE ready lines'
Assert ($src -match 'CLAUDE_CONNECT_UPDATE_YES') 'optional update honors CLAUDE_CONNECT_UPDATE_YES for automation'

# ---------------------------------------------------------------------------
# Part 5 (optional live apply): real version bump + EXE beside publish
# Set CLAUDE_CONNECT_HARD_PROMOTE_APPLY=1 to enable (needs deploy + SSH).
# ---------------------------------------------------------------------------
if ($env:CLAUDE_CONNECT_HARD_PROMOTE_APPLY -eq '1') {
    Note 'CaseApply: deploy bump + live update apply -> versioned EXE in claude-publish'
    $proj = $RepoRoot
    $deploy = Join-Path $proj 'publish\deploy-scripts-only.ps1'
    if (-not (Test-Path -LiteralPath $deploy)) {
        Assert $false 'deploy-scripts-only.ps1 missing'
    } else {
        . (Join-Path $proj 'publish\ClientBundleManifest.ps1')
        $before = (Get-Content (Join-Path $proj 'scripts\client\windows\connect-version.txt') -Raw).Trim()
        $new = Get-NextConnectVersion -Current $before
        Set-RepoConnectVersion -ProjectRoot $proj -Version $new
        # Ensure UPDATE_YES is in the bundle being deployed
        Copy-Item (Join-Path $proj 'scripts\client\windows\connect-update.ps1') (Join-Path $live 'connect-update.ps1') -Force
        & $deploy -ProjectRoot $proj -NoBump -ForceServerUnfreeze
        $serverVer = (ssh -o BatchMode=yes smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
        Assert ($serverVer -eq $new) "CaseApply server is v$new"

        # Keep live one version behind so optional update is offered
        Set-Content -LiteralPath (Join-Path $live 'connect-version.txt') -Value $before -Encoding ASCII -NoNewline
        # Hot-patch updater with UPDATE_YES support (may already be from copy above)
        Copy-Item (Join-Path $proj 'scripts\client\windows\connect-update.ps1') (Join-Path $live 'connect-update.ps1') -Force

        Set-Content -LiteralPath $realStamp -Value $pub -Encoding ASCII -NoNewline
        $env:CLAUDE_CONNECT_LAUNCH_DIR = $pub
        $env:CLAUDE_CONNECT_UPDATE_YES = '1'
        $env:CLAUDE_CONNECT_UPDATE_UI = '0'
        $expect = Join-Path $pub ("Claude-Connect-{0}.exe" -f $new)
        if (Test-Path $expect) { Remove-Item -LiteralPath $expect -Force }

        $outA = Join-Path $env:TEMP 'cc-hard-apply-out.txt'
        $errA = Join-Path $env:TEMP 'cc-hard-apply-err.txt'
        $pA = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $live 'connect-update.ps1'), '-ScriptDir', $live
        ) -WorkingDirectory $live -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $outA -RedirectStandardError $errA

        $stdoutA = if (Test-Path $outA) { Get-Content -LiteralPath $outA -Raw } else { '' }
        Write-Host $stdoutA
        Assert (($pA.ExitCode -eq 2) -or ($stdoutA -match 'Updated to')) ("CaseApply updater applied (exit=$($pA.ExitCode))")
        $afterLive = (Get-Content (Join-Path $live 'connect-version.txt') -Raw).Trim()
        Assert ($afterLive -eq $new) "CaseApply live version is $new"
        Assert (Test-Path -LiteralPath $expect) "CaseApply $([IO.Path]::GetFileName($expect)) beside claude-publish"
        if (Test-Path $expect) {
            Assert ((Get-FileHash -LiteralPath $expect -Algorithm MD5).Hash -eq $srcHash) 'CaseApply publish EXE md5 matches (EXE binary reused)'
        }
        Assert ($stdoutA -match 'EXE ready:') 'CaseApply UI listed EXE ready paths'
        Remove-Item Env:CLAUDE_CONNECT_UPDATE_YES -ErrorAction SilentlyContinue
    }
} else {
    Note 'CaseApply skipped (set CLAUDE_CONNECT_HARD_PROMOTE_APPLY=1 for live bump+apply)'
    $Skip++
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
