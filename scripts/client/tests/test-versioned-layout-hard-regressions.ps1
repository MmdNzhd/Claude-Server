#Requires -Version 5.1
# test-versioned-layout-hard-regressions.ps1
#
# HARD++ never-again for versioned Claude-Connect bugs caught 2026-07-27:
#   A) Update promote wrote Claude-Connect-NEW.exe into OLD \{ver}\ (2 EXEs / folder)
#   B) Instant Claude-Connect.cmd left an orphan titled cmd console that never closed
#   C) Bare Claude-Connect.exe / root litter inside versioned trees
#
# Live proofs use REAL extracted helpers (not reimplemented). Soft contract asserts
# alone are not enough — each bug has a process/filesystem adversarial case.
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
Write-Host '=== HARD++: versioned layout regressions (EXE leak + orphan cmd) ===' -ForegroundColor White
Write-Host ''

$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$updPath = Get-ClientFile 'windows\connect-update.ps1'
Assert (Test-Path -LiteralPath $launchPath) 'setup-launch body exists'
Assert (Test-Path -LiteralPath $updPath) 'connect-update.ps1 exists'
$launchSrc = Get-Content -LiteralPath $launchPath -Raw
$updSrc = Get-Content -LiteralPath $updPath -Raw

# ---------------------------------------------------------------------------
# Part 0: static never-again contracts (fail closed before live)
# ---------------------------------------------------------------------------
Note 'Part0: static contracts'
Assert ($updSrc -match 'foreign_verdir') 'Sync logs/skips foreign_verdir (NEW.exe into OLD VerDir)'
Assert ($updSrc -match 'dirLeaf -ne \$verLabel') 'Sync compares VerDir leaf to VersionLabel'
Assert ($updSrc -match 'only the versioned filename \(one EXE, not two\)') 'documents one EXE per VerDir'
Assert ($updSrc -match '\$env:CLAUDE_CONNECT_LAUNCH_DIR = \$newVerDir') 'versioned_apply retargets LAUNCH_DIR to NEW VerDir'
Assert ($updSrc -match '-Value \$newVerDir') 'versioned_apply writes newVerDir into last-launch-dir stamp'

$syncFn = Get-FunctionSource -Content $updSrc -Name 'Sync-ConnectExeBesideClient'
Assert ($null -ne $syncFn) 'extracted Sync-ConnectExeBesideClient'
Assert ($syncFn -match 'foreign_verdir') 'Sync function body has foreign_verdir skip'
    Assert ($syncFn -match 'if \(\$isVerDir(\)| -and)') 'Sync treats VerDir specially'
Assert ($syncFn -match 'if \(-not \$isVerDir\)') 'bare Claude-Connect.exe promote only when NOT VerDir'

$instantFn = Get-FunctionSource -Content $launchSrc -Name 'Write-ConnectInstantLauncher'
Assert ($null -ne $instantFn) 'extracted Write-ConnectInstantLauncher'
Assert ($instantFn -match 'Claude-Connect\.vbs') 'instant launcher writes .vbs'
Assert ($instantFn -match 'wscript\.exe //B //Nologo') 'cmd trampoline hands off to hidden wscript'
Assert ($instantFn -match 'exit /b 0') 'cmd trampoline exits immediately'
Assert ($instantFn -notmatch 'start "Claude Connect" /D') 'rejects old start "title" /D powershell form (orphan cmd)'
Assert ($instantFn -notmatch 'start "Claude Connect".*powershell\.exe') 'cmd does not start powershell directly'
Assert ($instantFn -match 'sh\.Run .*powershell\.exe') 'VBS starts powershell UI (window style 1)'

$liveExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
if (-not (Test-Path -LiteralPath $liveExe)) {
    $cands = @(
        (Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)),
        (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
    )
    foreach ($c in $cands) {
        if (Test-Path -LiteralPath $c) { $liveExe = $c; break }
    }
}
if (-not (Test-Path -LiteralPath $liveExe)) {
    Write-Host '  FAIL  no seed Claude-Connect.exe for live hard cases' -ForegroundColor Red
    $Fail++
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}
$srcHash = (Get-FileHash -LiteralPath $liveExe -Algorithm MD5).Hash
Note ("seed EXE md5=$srcHash")

# ---------------------------------------------------------------------------
# Part 1: extract REAL promote helpers
# ---------------------------------------------------------------------------
Note 'Part1: extract Sync + layout helpers from shipped connect-update.ps1'
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
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.20'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        if ($n -eq 'Test-ConnectLaunchDirUsable') {
            [void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param([string]$Dir) if(-not $Dir){return $false}; try { $full=[IO.Path]::GetFullPath($Dir) } catch { return $false }; if($full -match ''(?i)(?:^|[\\/])(?:WindowsPowerShell|System32|SysWOW64)(?:[\\/]|$)''){return $false}; return $true }')
            continue
        }
        Assert $false "extract $n"; throw "missing $n"
    }
    [void]$chunk.AppendLine($fn)
    [void]$chunk.AppendLine('')
}
$chunkText = $chunk.ToString()
$chunkText = $chunkText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$script:TestHardStamp'
$chunkText = $chunkText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'
Assert ($chunkText -match '\$script:TestHardStamp') 'sandbox rewrote stamp path (no real ~/.config touch)'

$root = Join-Path $env:TEMP ("cc-ver-hard-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$stampFile = Join-Path $root 'last-launch-dir.txt'
$null = New-Item -ItemType Directory -Force -Path $root
$script:TestHardStamp = $stampFile

try {
    Invoke-Expression $chunkText
    Assert $true 'loaded Sync + promote helpers'

    # ---- CaseA: adversarial promote — OLD VerDir must not receive NEW.exe ----
    Note 'CaseA: stamp+LAUNCH_DIR+env all point at OLD VerDir; promote NEW'
    $appRoot = Join-Path $root 'Claude-Connect'
    $oldVer = '20990101.10'
    $newVer = '20990101.20'
    $oldVerDir = Join-Path $appRoot $oldVer
    $newVerDir = Join-Path $appRoot $newVer
    $oldSrc = Join-Path $oldVerDir 'src'
    $newSrc = Join-Path $newVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $oldSrc, $newSrc
    Set-Content -LiteralPath (Join-Path $oldSrc 'connect.ps1') -Value '# stub-old' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $newSrc 'connect.ps1') -Value '# stub-new' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $oldSrc 'connect-boot.ps1') -Value '# stub-old-boot' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $newSrc 'connect-boot.ps1') -Value '# stub-new-boot' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $appRoot 'current.txt') -Value $newVer -Encoding ASCII -NoNewline
    Copy-Item -LiteralPath $liveExe -Destination (Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $oldVer)) -Force
    Copy-Item -LiteralPath $liveExe -Destination (Join-Path $newVerDir ("Claude-Connect-{0}.exe" -f $newVer)) -Force

    $ScriptDir = $newSrc
    $env:CLAUDE_CONNECT_VER_DIR = $newVerDir
    $env:CLAUDE_CONNECT_ROOT = $appRoot
    # Hostile: every external pointer still aims at the OLD folder (the real bug trigger).
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $oldVerDir
    Set-Content -LiteralPath $stampFile -Value $oldVerDir -Encoding ASCII -NoNewline

    Sync-ConnectExeBesideClient -VersionLabel $newVer

    $leak = Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $newVer)
    $oldOwn = Join-Path $oldVerDir ("Claude-Connect-{0}.exe" -f $oldVer)
    $newOwn = Join-Path $newVerDir ("Claude-Connect-{0}.exe" -f $newVer)
    $oldExes = @(Get-ChildItem -LiteralPath $oldVerDir -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    $newExes = @(Get-ChildItem -LiteralPath $newVerDir -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    $rootExes = @(Get-ChildItem -LiteralPath $appRoot -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    $oldBare = Join-Path $oldVerDir 'Claude-Connect.exe'
    $newBare = Join-Path $newVerDir 'Claude-Connect.exe'
    $srcLeakOld = @(Get-ChildItem -LiteralPath $oldSrc -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)
    $srcLeakNew = @(Get-ChildItem -LiteralPath $newSrc -Filter 'Claude-Connect*.exe' -File -ErrorAction SilentlyContinue)

    Assert (-not (Test-Path -LiteralPath $leak)) 'CaseA NO Claude-Connect-NEW.exe inside OLD VerDir'
    Assert (Test-Path -LiteralPath $oldOwn) 'CaseA OLD VerDir keeps its own EXE'
    Assert (Test-Path -LiteralPath $newOwn) 'CaseA NEW VerDir keeps matching EXE'
    Assert ($oldExes.Count -eq 1) ("CaseA OLD VerDir has exactly 1 EXE (got $($oldExes.Count): $($oldExes.Name -join ','))")
    Assert ($newExes.Count -eq 1) ("CaseA NEW VerDir has exactly 1 EXE (got $($newExes.Count): $($newExes.Name -join ','))")
    Assert ($oldExes[0].Name -eq ("Claude-Connect-{0}.exe" -f $oldVer)) 'CaseA OLD EXE name matches folder ver'
    Assert ($newExes[0].Name -eq ("Claude-Connect-{0}.exe" -f $newVer)) 'CaseA NEW EXE name matches folder ver'
    Assert (-not (Test-Path -LiteralPath $oldBare)) 'CaseA no bare Claude-Connect.exe in OLD VerDir'
    Assert (-not (Test-Path -LiteralPath $newBare)) 'CaseA no bare Claude-Connect.exe in NEW VerDir'
    Assert ($rootExes.Count -eq 0) 'CaseA no EXE litter at Claude-Connect root'
    Assert ($srcLeakOld.Count -eq 0) 'CaseA no EXE inside OLD src\'
    Assert ($srcLeakNew.Count -eq 0) 'CaseA no EXE inside NEW src\'

    # ---- CaseB: promoteDirs may LIST old VerDir, Sync must still skip write ----
    Note 'CaseB: Get-ConnectExePromoteDirs includes old stamp; Sync still skips'
    $pd = @(Get-ConnectExePromoteDirs -WinDir $newVerDir)
    $fullOld = [IO.Path]::GetFullPath($oldVerDir)
    $fullNew = [IO.Path]::GetFullPath($newVerDir)
    Assert (@($pd | Where-Object { $_ -eq $fullOld }).Count -ge 1) 'CaseB promoteDirs still lists OLD stamp (realistic)'
    Assert (@($pd | Where-Object { $_ -eq $fullNew }).Count -ge 1) 'CaseB promoteDirs lists NEW VerDir'
    # Second sync must remain idempotent / non-leaking
    Sync-ConnectExeBesideClient -VersionLabel $newVer
    Assert (-not (Test-Path -LiteralPath $leak)) 'CaseB second Sync still does not leak NEW into OLD'
    Assert (@(Get-ChildItem -LiteralPath $oldVerDir -Filter 'Claude-Connect*.exe' -File).Count -eq 1) 'CaseB OLD still exactly 1 EXE after resync'

} catch {
    Write-Host ("  FAIL  promote sandbox exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_VER_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_ROOT -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Part 2: instant launcher — REAL Write-ConnectInstantLauncher + orphan cmd proof
# ---------------------------------------------------------------------------
Note 'Part2: instant launcher VBS/cmd — no orphan cmd console'
try {
    $launchChunk = New-Object System.Text.StringBuilder
    [void]$launchChunk.AppendLine('$ErrorActionPreference = ''Continue''')
    [void]$launchChunk.AppendLine('function Log([string]$m) { }')
    $wif = Get-FunctionSource -Content $launchSrc -Name 'Write-ConnectInstantLauncher'
    if (-not $wif) { throw 'Write-ConnectInstantLauncher missing' }
    [void]$launchChunk.AppendLine($wif)
    Invoke-Expression $launchChunk.ToString()

    $instRoot = Join-Path $root 'instant'
    $instVerDir = Join-Path $instRoot '20990101.30'
    $instSrc = Join-Path $instVerDir 'src'
    $null = New-Item -ItemType Directory -Force -Path $instSrc
    # Marker file so we can prove boot ran without opening real Connect UI.
    $marker = Join-Path $instRoot 'boot-ran.txt'
    $bootBody = @"
`$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath '$($marker -replace "'", "''")' -Value ('booted ' + (Get-Date -Format o)) -Encoding ASCII
Start-Sleep -Seconds 2
"@
    Set-Content -LiteralPath (Join-Path $instSrc 'connect-boot.ps1') -Value $bootBody -Encoding ASCII

    Write-ConnectInstantLauncher -VerDir $instVerDir -SrcDir $instSrc
    $vbs = Join-Path $instVerDir 'Claude-Connect.vbs'
    $cmd = Join-Path $instVerDir 'Claude-Connect.cmd'
    Assert (Test-Path -LiteralPath $vbs) 'CaseC wrote Claude-Connect.vbs'
    Assert (Test-Path -LiteralPath $cmd) 'CaseC wrote Claude-Connect.cmd'
    $cmdText = Get-Content -LiteralPath $cmd -Raw
    $vbsText = Get-Content -LiteralPath $vbs -Raw
    Assert ($cmdText -match 'wscript\.exe //B //Nologo') 'CaseC cmd hands off to wscript //B'
    Assert ($cmdText -match 'exit /b 0') 'CaseC cmd exits'
    Assert ($cmdText -notmatch 'start "Claude Connect"') 'CaseC cmd has no titled start (orphan pattern)'
    Assert ($vbsText -match 'sh\.Run') 'CaseC VBS uses WScript.Shell.Run'
    Assert ($vbsText -match 'connect-boot\.ps1') 'CaseC VBS targets connect-boot.ps1'

    # Kill any prior leftover from earlier tests with same marker name (none expected).
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

    # Launch via .cmd (Explorer-equivalent host: cmd /c).
    $pCmd = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @(
        '/d', '/c', "`"$cmd`""
    ) -WorkingDirectory $instVerDir -PassThru -WindowStyle Normal
    Assert ($null -ne $pCmd) 'CaseC started cmd /c Claude-Connect.cmd'

    $deadline = [datetime]::UtcNow.AddSeconds(8)
    $bootOk = $false
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $marker) { $bootOk = $true; break }
        Start-Sleep -Milliseconds 150
    }
    Assert $bootOk 'CaseC connect-boot actually ran (marker written)'

    # Give trampoline time to exit; then prove no orphan cmd still hosting the launcher.
    Start-Sleep -Milliseconds 800
    $orphans = @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        if (-not $cl) { return $false }
        # Any cmd still running OUR launcher path after boot is an orphan.
        return ($cl -match [regex]::Escape($cmd)) -or ($cl -match [regex]::Escape($instVerDir) -and $cl -match 'Claude-Connect\.cmd')
    })
    Assert ($orphans.Count -eq 0) ("CaseC no orphan cmd after launch (got $($orphans.Count))")
    if ($orphans.Count -gt 0) {
        foreach ($o in $orphans) {
            Write-Host ("         orphan pid=$($o.ProcessId) cl=$($o.CommandLine)") -ForegroundColor DarkYellow
            try { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # Also launch VBS directly — must boot without any cmd parent.
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $pVbs = Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList @(
        '//B', '//Nologo', "`"$vbs`""
    ) -WorkingDirectory $instVerDir -PassThru -WindowStyle Hidden
    Assert ($null -ne $pVbs) 'CaseD started wscript Claude-Connect.vbs'
    $deadline2 = [datetime]::UtcNow.AddSeconds(8)
    $bootOk2 = $false
    while ([datetime]::UtcNow -lt $deadline2) {
        if (Test-Path -LiteralPath $marker) { $bootOk2 = $true; break }
        Start-Sleep -Milliseconds 150
    }
    Assert $bootOk2 'CaseD VBS path boots connect-boot (marker)'
    Start-Sleep -Milliseconds 500
    $orphans2 = @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        $cl -and ($cl -match [regex]::Escape($instVerDir)) -and ($cl -match 'Claude-Connect')
    })
    Assert ($orphans2.Count -eq 0) 'CaseD VBS path left zero Claude-Connect cmd processes'

    # Cleanup boot powershell stubs
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($instSrc))
    } | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
} catch {
    Write-Host ("  FAIL  instant-launcher sandbox exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

# ---------------------------------------------------------------------------
# Part 3: negative pattern — old bad .cmd form must not reappear in publish body
# ---------------------------------------------------------------------------
Note 'Part3: fail-closed on known-bad launcher patterns'
Assert ($launchSrc -notmatch 'start "Claude Connect" /D "%SRC%" powershell') `
    'publish body must never resurrect titled start+powershell orphan pattern'
Assert ($launchSrc -match 'Write-ConnectInstantLauncher') 'publish body still has instant launcher writer'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARD++ RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("HARD++ RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
