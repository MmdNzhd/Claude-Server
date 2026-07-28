#Requires -Version 5.1
# test-harder-adversarial.ps1
# HARD+++ adversarial gate beyond never-again / hard-cmd / promote-hard:
#   A) Live triple-parity: repo == server bundle == claude-publish EXE
#   B) Live server ship-gates (no STALE-SHADOW, no r-truncation, proxy/update strings)
#   C) Publish EXE string scan (no powershell Bypass AppLaunched; hidden wscript path)
#   D) Portable bad-dir matrix (System32 / PowerShell / IXP / extract-src rejected)
#   E) Concurrent promote stress (4 isolated stamps, no shared last-launch-dir race)
#   F) UI-first worker (skip pre-boot network update; debounce <= 500ms)
#   G) Corruption canaries that ship-gate regexes MUST catch
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
Write-Host '=== HARD+++: adversarial (live + EXE + portable + stress) ===' -ForegroundColor White
Write-Host ''

$sshBin = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path -LiteralPath $sshBin)) { $sshBin = 'ssh' }
$sshOpts = @('-F', 'NUL', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20', '-o', 'StrictHostKeyChecking=accept-new')
$Server = 'smart@192.168.210.240'
$Bundle = '/usr/local/share/claude-client'

$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
Assert ($repoVer -match '^\d{8}\.\d+$') "repo connect-version parseable ($repoVer)"

# ---------------------------------------------------------------------------
# A) Live triple-parity
# ---------------------------------------------------------------------------
Note 'A) live triple-parity (repo / server / publish EXE)'
$pubDir = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$pubExe = Join-Path $pubDir ("Claude-Connect-{0}.exe" -f $repoVer)
Assert (Test-Path -LiteralPath $pubExe) ("publish has Claude-Connect-{0}.exe" -f $repoVer)

$remoteVer = ''
try {
    $remoteVer = (& $sshBin @sshOpts $Server "cat $Bundle/connect-version.txt" 2>$null | Out-String).Trim()
} catch { $remoteVer = '' }
if (-not $remoteVer) {
    Write-Host '  FAIL  cannot SSH-read server connect-version.txt' -ForegroundColor Red
    $Fail++
} else {
    Assert ($remoteVer -eq $repoVer) ("server bundle version == repo ($repoVer)")
}

# Key script presence + CRLF-normalized SHA256 parity (repo -> server)
$parityFiles = @(
    @{ Rel = 'windows\connect.ps1'; Remote = 'connect.ps1' },
    @{ Rel = 'windows\connect-update.ps1'; Remote = 'connect-update.ps1' },
    @{ Rel = 'connect-ui.ps1'; Remote = 'connect-ui.ps1' },
    @{ Rel = 'connect-diagnostic.ps1'; Remote = 'connect-diagnostic.ps1' },
    @{ Rel = 'windows\cursor-proxy-sidecar.ps1'; Remote = 'cursor-proxy-sidecar.ps1' }
)
$scpBin = Join-Path $env:SystemRoot 'System32\OpenSSH\scp.exe'
if (-not (Test-Path -LiteralPath $scpBin)) { $scpBin = 'scp' }

function Invoke-RemoteBash([string]$Body, [string]$Tag) {
    $local = Join-Path $env:TEMP ("cc-harder-{0}-{1}.sh" -f $Tag, [guid]::NewGuid().ToString('N').Substring(0, 8))
    $remote = "/tmp/cc-harder-$Tag-$(([guid]::NewGuid().ToString('N').Substring(0, 8))).sh"
    # LF-only for remote bash
    $lf = ($Body -replace "`r`n", "`n" -replace "`r", "`n")
    [IO.File]::WriteAllText($local, $lf, [Text.UTF8Encoding]::new($false))
    try {
        & $scpBin @sshOpts $local "${Server}:$remote" 2>$null | Out-Null
        # PowerShell: escape $? / $ec with backtick (backslash does NOT escape $).
        $out = (& $sshBin @sshOpts $Server "bash '$remote'; ec=`$?; rm -f '$remote'; exit `$ec" 2>$null | Out-String)
        return $out
    } finally {
        Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    }
}

$remoteHashOut = Invoke-RemoteBash @'
set -e
B=/usr/local/share/claude-client
for f in connect.ps1 connect-update.ps1 connect-ui.ps1 connect-diagnostic.ps1 cursor-proxy-sidecar.ps1; do
  # Normalize CRLF before hash so Windows repo vs Linux strip can match.
  h=$(tr -d '\r' < "$B/$f" | sha256sum | awk '{print toupper($1)}')
  echo "$f=$h"
done
'@ 'hash'
Assert ($remoteHashOut -match 'connect\.ps1=') 'SSH returned server file hashes'

foreach ($pf in $parityFiles) {
    $localPath = Get-ClientFile $pf.Rel
    if (-not (Test-Path -LiteralPath $localPath)) {
        Assert $false ("local missing $($pf.Rel)")
        continue
    }
    $norm = [IO.File]::ReadAllBytes($localPath)
    # Strip CR bytes for fair compare with server tr -d '\r'
    $norm2 = New-Object System.Collections.Generic.List[byte]
    foreach ($b in $norm) { if ($b -ne 13) { [void]$norm2.Add($b) } }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $localHash = ([BitConverter]::ToString($sha.ComputeHash($norm2.ToArray())) -replace '-', '').ToUpperInvariant()
    } finally { $sha.Dispose() }
    $m = [regex]::Match($remoteHashOut, [regex]::Escape($pf.Remote) + '=([A-F0-9]{64})')
    if (-not $m.Success) {
        Assert $false ("server hash missing for $($pf.Remote)")
        continue
    }
    Assert ($localHash -eq $m.Groups[1].Value) ("CRLF-normalized SHA256 parity $($pf.Remote)")
}

# ---------------------------------------------------------------------------
# B) Live server ship-gates (content, not just deploy script text)
# ---------------------------------------------------------------------------
Note 'B) live server ship-gates on staged bundle'
$gateOut = Invoke-RemoteBash @'
set -e
B=/usr/local/share/claude-client
pass() { echo "LIVE_GATE_PASS $1"; }
bad()  { echo "LIVE_GATE_FAIL $1"; }
# diagnostic must be canon
if grep -q 'STALE-SHADOW REPLACED' "$B/connect-diagnostic.ps1" 2>/dev/null; then
  bad 'diagnostic_stale_shadow'
else
  pass 'diagnostic_not_shadow'
fi
grep -q 'Get-ConnectProblemVerdict' "$B/connect-diagnostic.ps1" && pass 'diagnostic_verdict' || bad 'diagnostic_verdict'
# no r-truncation
if grep -qE '\$uidSt[^r]|Get-InteractiveLaptopUse[^r]' "$B/connect.ps1" 2>/dev/null; then
  bad 'connect_r_truncation'
else
  pass 'connect_no_r_truncation'
fi
grep -q '\$uidStr' "$B/connect.ps1" && pass 'connect_uidStr' || bad 'connect_uidStr'
grep -q 'Get-InteractiveLaptopUser' "$B/connect.ps1" && pass 'connect_InteractiveUser' || bad 'connect_InteractiveUser'
grep -q '\$OnFolder' "$B/connect-diagnostic.ps1" && pass 'diag_OnFolder' || bad 'diag_OnFolder'
# proxy
grep -q 'CURSOR_PROXY_CLEAR force reason=backend_down' "$B/cursor-proxy-sidecar.ps1" && pass 'sidecar_backend_down' || bad 'sidecar_backend_down'
grep -q 'SIDECAR_ENSURE front_up backend_down stopping_fronts_clearing_settings' "$B/cursor-proxy-sidecar.ps1" && pass 'sidecar_stop_fronts' || bad 'sidecar_stop_fronts'
# update hard exit
grep -q 'Stop-Process -Id \$PID -Force' "$B/connect-ui.ps1" && pass 'ui_hard_kill' || bad 'ui_hard_kill'
grep -q "update_manual_relaunch" "$B/connect-ui.ps1" && pass 'ui_update_relaunch' || bad 'ui_update_relaunch'
# promote helpers
grep -q 'Get-ConnectExePromoteDirs' "$B/connect-update.ps1" && pass 'update_promote_dirs' || bad 'update_promote_dirs'
grep -q 'Copy-ExeAtomicSwap' "$B/connect-update.ps1" && pass 'update_atomic_swap' || bad 'update_atomic_swap'
# EXE present
[ -f "$B/Claude-Connect.exe" ] && pass 'bundle_exe_present' || bad 'bundle_exe_present'
# size floors
sz=$(wc -c < "$B/connect-diagnostic.ps1")
[ "$sz" -ge 5000 ] && pass 'diagnostic_size' || bad "diagnostic_size_$sz"
'@ 'gates'
$gateFails = @([regex]::Matches($gateOut, 'LIVE_GATE_FAIL\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
$gatePasses = @([regex]::Matches($gateOut, 'LIVE_GATE_PASS\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
Assert ($gatePasses.Count -ge 12) ("live ship-gates >=12 PASS (got $($gatePasses.Count))")
Assert ($gateFails.Count -eq 0) ("live ship-gates zero FAIL (got: $($gateFails -join ','))")

# ---------------------------------------------------------------------------
# C) Publish EXE string scan
# ---------------------------------------------------------------------------
Note 'C) publish EXE AppLaunched / hidden launcher strings'
if (-not (Test-Path -LiteralPath $pubExe)) {
    Assert $false ("skip EXE string scan - missing Claude-Connect-{0}.exe" -f $repoVer)
} else {
    $exeBytes = [IO.File]::ReadAllBytes($pubExe)
    $exeAscii = -join ($exeBytes | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { ' ' } })
    $exeAscii = [regex]::Replace($exeAscii, '\s+', ' ')
    Assert ($exeAscii -match 'setup-run-hidden\.vbs') 'EXE embeds setup-run-hidden.vbs'
    Assert ($exeAscii -match 'wscript\.exe') 'EXE embeds wscript.exe launcher'
    Assert ($exeAscii -match 'setup-claude-connect\.cmd') 'EXE embeds setup-claude-connect.cmd'
    Assert ($exeAscii -notmatch 'AppLaunched=powershell\.exe') 'EXE AppLaunched is not raw powershell.exe'
    Assert ($exeAscii -notmatch 'ExecutionPolicy Bypass.*WindowStyle Hidden|WindowStyle Hidden.*ExecutionPolicy Bypass') `
        'EXE does not embed Bypass+Hidden powershell AppLaunched heuristic'
    Assert ($exeBytes.Length -ge 200000) ("publish EXE size floor >=200KB (got $($exeBytes.Length))")
}

# ---------------------------------------------------------------------------
# D) Portable bad-dir matrix (real extracted helpers)
# ---------------------------------------------------------------------------
Note 'D) portable Test-IsBadInstallDir matrix'
$launchSrc = Get-Content (Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1') -Raw
$badFn = Get-FunctionSource -Content $launchSrc -Name 'Test-IsBadInstallDir'
Assert ($null -ne $badFn) 'extracted Test-IsBadInstallDir'
$resolveFn = Get-FunctionSource -Content $launchSrc -Name 'Resolve-ConnectLaunchExe'
if (-not $resolveFn) { $resolveFn = Get-FunctionSource -Content $launchSrc -Name 'Resolve-VersionedTree' }
Assert ($null -ne $resolveFn) 'extracted launch/versioned resolver'
Assert ($launchSrc -match 'fallback_desktop') 'portable keeps Desktop fallback'
Assert ($launchSrc -match 'parent_chain') 'portable walks parent process chain'
Assert ($launchSrc -match 'CLAUDE_CONNECT_INSTALL_DIR') 'portable stamps INSTALL_DIR'
Assert ($launchSrc -match 'Resolve-VersionedTree|Test-VersionSrcComplete') 'versioned Claude-Connect/{ver}/src layout'

if ($badFn) {
    $extractSrc = Join-Path $env:TEMP 'IXP000.TMP'
    Invoke-Expression $badFn
    $cases = @(
        @{ Dir = (Join-Path $env:WINDIR 'System32'); ExpectBad = $true; Name = 'System32' },
        @{ Dir = (Join-Path $env:WINDIR 'SysWOW64'); ExpectBad = $true; Name = 'SysWOW64' },
        @{ Dir = 'C:\Windows\System32\WindowsPowerShell\v1.0'; ExpectBad = $true; Name = 'WindowsPowerShell' },
        @{ Dir = (Join-Path $env:TEMP 'IXP000.TMP'); ExpectBad = $true; Name = 'IExpress IXP temp' },
        @{ Dir = (Join-Path $env:TEMP 'wextract_fake'); ExpectBad = $true; Name = 'wextract temp name' },
        @{ Dir = $extractSrc; ExpectBad = $true; Name = 'same as ExtractSrc' },
        @{ Dir = (Join-Path $env:USERPROFILE 'Desktop\claude-publish'); ExpectBad = $false; Name = 'claude-publish ok' },
        @{ Dir = (Join-Path $env:TEMP 'test for update'); ExpectBad = $false; Name = 'portable temp folder ok' }
    )
    foreach ($c in $cases) {
        if ($c.Name -eq 'wextract temp name') {
            # function matches Temp\wextract* path pattern - ensure path shape
            $c.Dir = Join-Path $env:TEMP 'wextractABC'
        }
        if ($c.Name -eq 'portable temp folder ok' -and -not (Test-Path -LiteralPath $c.Dir)) {
            New-Item -ItemType Directory -Force -Path $c.Dir | Out-Null
        }
        $isBad = Test-IsBadInstallDir -Dir $c.Dir -ExtractSrc $extractSrc
        Assert (($isBad -eq $c.ExpectBad)) ("bad-dir $($c.Name) => $isBad (expect bad=$($c.ExpectBad))")
    }
}

# Worker UI-first contracts
$workerSrc = Get-Content (Join-Path $script:RepoRoot 'publish\_setup-worker-body.ps1') -Raw
Assert ($workerSrc -match 'preboot update skipped reason=manual_only') 'worker skips pre-boot update (manual menu u only)'
Assert ($workerSrc -notmatch 'CLAUDE_CONNECT_UPDATE_YES\s*=\s*''1''') 'worker does not auto-apply UPDATE_YES'
Assert ($workerSrc -match '\$debounceMs = (100|400)') 'worker debounce is 100ms or 400ms (<=500)'
Assert ($workerSrc -match 'ClaudeConnectExeLaunch') 'worker owns ExeLaunch mutex gate'
Assert ($workerSrc -match 'CLAUDE_CONNECT_INSTALL_DIR') 'worker honors INSTALL_DIR'

# ---------------------------------------------------------------------------
# E) Concurrent promote stress (isolated stamps)
# ---------------------------------------------------------------------------
Note 'E) concurrent promote stress x4'
$updSrc = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
$needed = @('Test-ConnectLaunchDirUsable', 'Get-ConnectVersionedLayout', 'Test-IsConnectVersionedSrcDir', 'Test-IsConnectVersionedRootDir', 'Get-SafeFileSha256', 'Copy-ExeAtomicSwap', 'Get-ConnectExePromoteDirs', 'Sync-ConnectExeBesideClient')
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$chunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.99'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        if ($n -eq 'Test-ConnectLaunchDirUsable') {
            [void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param([string]$Dir) if(-not $Dir){return $false}; try { $full=[IO.Path]::GetFullPath($Dir) } catch { return $false }; if($full -match ''(?i)(?:^|[\\/])(?:WindowsPowerShell|System32|SysWOW64)(?:[\\/]|$)''){return $false}; return $true }')
            continue
        }
        if ($n -eq 'Get-ConnectVersionedLayout') {
            [void]$chunk.AppendLine('function Get-ConnectVersionedLayout { param([string]$Dir) return $null }')
            continue
        }
        Assert $false "extract $n"; continue
    }
    [void]$chunk.AppendLine($fn)
}
$chunkText = $chunk.ToString()
$chunkText = $chunkText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$script:TestPromoteStamp'
$chunkText = $chunkText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'
Assert ($chunkText -match '\$script:TestPromoteStamp') 'stress helpers use isolated stamp'

$liveExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
if (-not (Test-Path -LiteralPath $liveExe)) { $liveExe = $pubExe }
Assert (Test-Path -LiteralPath $liveExe) 'stress source EXE exists'

$jobs = @()
$stressRoot = Join-Path $env:TEMP ("cc-harder-stress-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
1..4 | ForEach-Object {
    $i = $_
    $jobs += Start-Job -ScriptBlock {
        param($Chunk, $LiveExe, $Root, $Idx, $SrcHash)
        $ErrorActionPreference = 'Stop'
        $dir = Join-Path $Root ("slot-$Idx")
        $install = Join-Path $dir 'install'
        $launch = Join-Path $dir 'launch'
        $stamp = Join-Path $dir 'last-launch-dir.txt'
        New-Item -ItemType Directory -Force -Path $install, $launch | Out-Null
        Copy-Item -LiteralPath $LiveExe -Destination (Join-Path $install 'Claude-Connect.exe') -Force
        Set-Content -LiteralPath $stamp -Value $launch -Encoding ASCII -NoNewline
        $script:TestPromoteStamp = $stamp
        $ScriptDir = $install
        Remove-Item Env:CLAUDE_CONNECT_LAUNCH_DIR -ErrorAction SilentlyContinue
        Invoke-Expression $Chunk
        Sync-ConnectExeBesideClient -VersionLabel ('20990101.{0:D2}' -f $Idx)
        $ver = Join-Path $launch ('Claude-Connect-20990101.{0:D2}.exe' -f $Idx)
        $ok = (Test-Path -LiteralPath $ver) -and ((Get-FileHash -LiteralPath $ver -Algorithm MD5).Hash -eq $SrcHash)
        [pscustomobject]@{ Idx = $Idx; Ok = [bool]$ok; Path = $ver }
    } -ArgumentList $chunkText, $liveExe, $stressRoot, $i, ((Get-FileHash -LiteralPath $liveExe -Algorithm MD5).Hash)
}
$results = $jobs | Wait-Job -Timeout 90 | Receive-Job
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue
try { Remove-Item -LiteralPath $stressRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
$okCount = @($results | Where-Object { $_.Ok }).Count
Assert ($okCount -eq 4) ("concurrent promote 4/4 ok (got $okCount)")

# ---------------------------------------------------------------------------
# F) Corruption canaries (ship-gate regexes must match bad payloads)
# ---------------------------------------------------------------------------
Note 'F) corruption canaries for ship-gate patterns'
$dcb = Get-Content (Join-Path $script:RepoRoot 'scripts\server\commands\deploy-client-bundle.sh') -Raw
Assert ($dcb -match 'trailing-r strip corruption') 'deploy documents r-truncation gate'
Assert ($dcb -match '\$uidStr') 'deploy ship-gate greps $uidStr'
# Simulate truncated identifiers the BusyBox sed bug produced
$badConnect = '$uidSt = "x"`nfunction Get-InteractiveLaptopUse { }'
$goodConnect = '$uidStr = "x"`nfunction Get-InteractiveLaptopUser { }'
Assert ($badConnect -match '\$uidSt[^r]|Get-InteractiveLaptopUse[^r]') 'canary: truncated connect identifiers match reject pattern'
Assert ($goodConnect -notmatch '\$uidSt[^r]|Get-InteractiveLaptopUse[^r]') 'canary: good connect identifiers do not false-positive'
$badDiag = '$OnFolde = $true'
$goodDiag = '$OnFolder = $true'
Assert ($badDiag -match '\$OnFolde[^r]') 'canary: truncated $OnFolder matches reject pattern'
Assert ($goodDiag -notmatch '\$OnFolde[^r]') 'canary: good $OnFolder does not false-positive'

# ---------------------------------------------------------------------------
# G) Shadow must never equal staged diagnostic
# ---------------------------------------------------------------------------
Note 'G) windows/ shadow vs canon / staged'
$shadow = Get-Content (Get-ClientFile 'windows\connect-diagnostic.ps1') -Raw
$canon = Get-Content (Get-ClientFile 'connect-diagnostic.ps1') -Raw
Assert ($shadow -match 'STALE-SHADOW REPLACED') 'repo windows/ diagnostic is still a shadow marker'
Assert ($canon -notmatch 'STALE-SHADOW REPLACED') 'repo canon diagnostic is not a shadow'
Assert ($canon.Length -gt $shadow.Length) 'canon diagnostic larger than shadow stub'
Assert ($gateOut -notmatch 'LIVE_GATE_FAIL diagnostic_stale_shadow') 'staged server diagnostic is not shadow'

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
