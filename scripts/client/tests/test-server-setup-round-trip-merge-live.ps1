# test-server-setup-round-trip-merge-live.ps1 - Bug 12 LIVE: proves the mount/git hash-check
# remote command (formerly a SEPARATE SshX round trip issued AFTER Acquire-TunnelPort) is now
# folded into the SAME initial id-u/keygen/pubkey round trip in Initialize-ServerSession, and
# that the merged remote bash command is real, syntactically valid, and produces the expected
# UID/pubkey/MOUNT_HASH/GIT_HASH markers when actually executed - not just present as source text.
#
# Live evidence this responds to (2026-07-24): the "Server setup" step alone took 50049ms across
# 8 sequential one-shot ssh calls (this repo deliberately does not use SSH ControlMaster on
# Windows - each call pays a full fresh handshake, ~4.3-6.7s under real contention). This merge
# removes one of those 8 calls with zero data-dependency change (the hash values are only
# consumed later, to decide whether claude-mount.sh/claude-git-setup.sh need re-pushing - nothing
# between the old call site and the new one relies on ordering).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
# Bare `bash` on PATH can resolve to C:\WINDOWS\system32\bash.exe (the WSL launcher stub, a
# totally different filesystem/path-translation world - /c/... paths mean nothing to it) rather
# than Git Bash, depending on PATH ordering in the calling process - confirmed live in this
# environment. Pin explicitly to Git Bash so this test's /c/... MSYS-style paths are unambiguous.
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $gitBash)) {
    Write-Host "  FAIL  Git Bash not found at $gitBash - live test cannot run" -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host '=== Server setup round-trip merge (Bug 12) LIVE ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$fnSrc = Get-FunctionSource -Content $content -Name 'Initialize-ServerSession'
if (-not $fnSrc) {
    Write-Host "  FAIL  could not extract Initialize-ServerSession - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}

# --- Part 1: source-drift-allergic proof of the merge ---
Assert ($fnSrc -match "id -u.*ssh-keygen.*claude_laptop\.pub.*MOUNT_HASH.*GIT_HASH") `
    'FIXED: the id-u/keygen/pubkey call and the MOUNT_HASH/GIT_HASH markers are all present in ONE SshX command string'
$sshXCallCount = ([regex]::Matches($fnSrc, '\bSshX\s')).Count
Write-Host "  INFO  Initialize-ServerSession source contains $sshXCallCount bare 'SshX ' call sites (excludes Acquire-TunnelPort's own internal calls, which live in a separate function)" -ForegroundColor DarkGray
Assert ($fnSrc -notmatch '\$hashCmd\s*=') 'FIXED: the old separate $hashCmd remote-script variable no longer exists in this function'
Assert ($fnSrc -notmatch 'SshX\s+\$hashCmd') 'FIXED: no second SshX call issues the hash-check as its own round trip any more'

# --- Part 2: the merged-in hash-check tail is REAL, valid bash and produces the right markers ---
# (The leading id-u/keygen/pubkey portion is pre-existing, unchanged code - already covered by
# this repo's other live tests; this part only needs to prove the NEWLY-merged tail is correct.)
# Extract just the "mkdir ... MOUNT_HASH ... GIT_HASH" tail verbatim from source and execute it
# for real via Git Bash against a real temp HOME with real dummy files, proving the shell syntax
# (command substitution, awk, echo markers) is correct - not merely well-formed-looking text.
$rawTail = $null
if ($fnSrc -match 'SshX\s+\("([^"]+)"\s*\+\s*\$portProbeBash\)') {
    $fullRawCmd = $Matches[1]
    $tailIdx = $fullRawCmd.IndexOf('mkdir -p ~/.local/bin')
    if ($tailIdx -ge 0) {
        $rawTail = $fullRawCmd.Substring($tailIdx) -replace '\s*&&\s*$', ''
    }
} elseif ($fnSrc -match 'SshX\s+"([^"]*)"') {
    $fullRawCmd = $Matches[1]
    $tailIdx = $fullRawCmd.IndexOf('mkdir -p ~/.local/bin')
    if ($tailIdx -ge 0) {
        $rawTail = $fullRawCmd.Substring($tailIdx) -replace '\s*&&\s*$', ''
    }
}
if ($rawTail) {
    Assert $true 'extracted the real merged hash-check tail verbatim from source (full command string, no embedded double-quote to truncate on)'

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-serversetup-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'local\bin') | Out-Null
    Set-Content -LiteralPath (Join-Path $tmp 'local\bin\claude-mount') -Value 'dummy-mount-content' -NoNewline
    Set-Content -LiteralPath (Join-Path $tmp 'local\bin\claude-git-setup') -Value 'dummy-git-setup-content' -NoNewline
    $expectMountHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $tmp 'local\bin\claude-mount')).Hash.ToLower()
    $expectGitHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $tmp 'local\bin\claude-git-setup')).Hash.ToLower()

    # PowerShell's double-quoted source string escapes `$( as a literal backtick+dollar - reverse
    # that so real bash sees real command substitution. Rewrite ~/.local -> $TESTHOME/local so a
    # plain env var drives the path (no fragile ~ / HOME interaction). Write to a real .sh FILE
    # and invoke it (rather than -c "...") to avoid PowerShell-string-inside-bash-string quoting
    # hazards entirely - a real script file is exactly how these commands run for real anyway
    # (SshX ships the whole string as one remote command, not nested shell-in-shell quoting).
    $bashCmd = ($rawTail -replace '`\$', '$') -replace '~/\.local', '$TESTHOME/local'
    $winTestHome = ($tmp -replace '\\', '/')
    $drive = $winTestHome.Substring(0, 1).ToLower()
    $testHome = "/$drive" + $winTestHome.Substring(2)
    $scriptFile = Join-Path $tmp 'run.sh'
    Set-Content -LiteralPath $scriptFile -Value "export TESTHOME='$testHome'`n$bashCmd`n" -NoNewline -Encoding ASCII
    $scriptFileBashPath = "$testHome/run.sh"
    $realOut = & $gitBash $scriptFileBashPath 2>&1
    Write-Host "  INFO  real bash output:`n$($realOut -join "`n" | ForEach-Object { "    $_" })" -ForegroundColor DarkGray

    # Same [string](... + '') guard as connect.ps1: when bash emits no hash line the
    # Where-Object is empty and -replace over it yields an empty Object[], whose .Trim()
    # is a terminating error - that would crash the runner instead of failing the assert.
    $outMountHash = (([string](($realOut | Where-Object { $_ -match '^MOUNT_HASH:' } | Select-Object -First 1) + '')) -replace '^MOUNT_HASH:', '').Trim()
    $outGitHash = (([string](($realOut | Where-Object { $_ -match '^GIT_HASH:' } | Select-Object -First 1) + '')) -replace '^GIT_HASH:', '').Trim()

    Assert ($outMountHash -eq $expectMountHash) "real MOUNT_HASH ($outMountHash) matches the real sha256sum of the dummy claude-mount file ($expectMountHash) - hash-check logic survived the merge intact"
    Assert ($outGitHash -eq $expectGitHash) "real GIT_HASH ($outGitHash) matches the real sha256sum of the dummy claude-git-setup file ($expectGitHash) - hash-check logic survived the merge intact"

    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  FAIL  could not extract the merged hash-check tail from source (source drifted)" -ForegroundColor Red
    $fail++
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): Bug 12 is FIXED - the hash-check round trip is merged into the initial id-u/keygen/pubkey call, saving one full ssh handshake per connect, and the merged command is real, valid bash producing correct hashes.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
