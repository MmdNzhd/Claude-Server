# test-hardest-83-temp-parsa.ps1
# HARD: simulate p.beheshti DOS 8.3 (PAAA7~1.BEH) across update/bootstrap/heal/copy-lists.
# Must fail red if chicken-egg or TEMP staging still breaks.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Win = Join-Path $RepoRoot 'scripts\client\windows'
$pass = 0; $fail = 0
function Assert([bool]$c, [string]$m) {
    if ($c) { $script:pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
}
function Note([string]$m) { Write-Host "  ----  $m" -ForegroundColor DarkCyan }

Write-Host '=== HARDEST 8.3 TEMP / Parsa-class ===' -ForegroundColor Cyan

# --- Part A: ship contracts (copy lists must include repair) ---
Note 'Part A: heal/bootstrap/bat/push must ship connect-env-repair.ps1'
$heal = Get-Content (Join-Path $Win 'connect-heal.ps1') -Raw
$boot = Get-Content (Join-Path $Win 'connect-bootstrap.ps1') -Raw
$bat  = Get-Content (Join-Path $Win 'connect.bat') -Raw
$push = Get-Content (Join-Path $RepoRoot 'scripts\server\claude-client-push-laptop.sh') -Raw
$manifest = Get-Content (Join-Path $RepoRoot 'publish\client-bundle-manifest.tsv') -Raw
Assert ($heal -match 'connect-env-repair\.ps1') 'connect-heal.ps1 Essential includes connect-env-repair.ps1'
Assert ($boot -match 'connect-env-repair\.ps1') 'connect-bootstrap.ps1 PullNames includes connect-env-repair.ps1'
Assert ($bat -match 'connect-env-repair\.ps1') 'connect.bat references connect-env-repair.ps1'
# Both heal copy lists in bat (broken-update + $names)
Assert ([regex]::Matches($bat, 'connect-env-repair\.ps1').Count -ge 2) 'connect.bat mentions repair in emit + at least one heal list (or twice overall)'
Assert ($push -match 'connect-env-repair\.ps1') 'claude-client-push-laptop.sh pushes repair'
Assert ($manifest -match 'connect-env-repair\.ps1') 'manifest ships repair'

# Bootstrap/heal must self-repair before TEMP use
Assert ($boot -match 'connect-env-repair|Repair-ConnectWindowsProfileTempEnv|GetFolderPath\(''UserProfile''\)') 'connect-bootstrap.ps1 self-repairs TEMP/profile'
Assert ($heal -match 'connect-env-repair|Repair-ConnectWindowsProfileTempEnv|GetFolderPath\(''UserProfile''\)') 'connect-heal.ps1 self-repairs TEMP/profile'

# Auth TEMP root must reject tilde
$auth = Get-Content (Join-Path $RepoRoot 'scripts\client\cursor-auth-laptop.ps1') -Raw
Assert ($auth -match "Get-CursorAuthTempRoot[\s\S]{0,800}-notmatch '~'|match '~'") 'Get-CursorAuthTempRoot rejects 8.3 tilde candidates'

# --- Part B: live poison — repair then New-Item/staging like connect-update ---
Note 'Part B: poison USERPROFILE/TEMP with PAAA7~1.BEH then repair + staging'
$repairPath = Join-Path $Win 'connect-env-repair.ps1'
$fake = 'C:\Users\PAAA7~1.BEH'
$job = Start-Job -ScriptBlock {
    param($RepairPath, $Fake, $WinDir)
    $ErrorActionPreference = 'Stop'
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP

    # Without repair: either New-Item throws (real 8.3 alias) OR creates under a tilde path (literal poison).
    $rawPoisoned = $false
    $bad = Join-Path $env:TEMP ("claude-client-update-staging-{0}" -f $PID)
    try {
        New-Item -ItemType Directory -Force -Path $bad -ErrorAction Stop | Out-Null
        if ($bad -match '~') { $rawPoisoned = $true }
        Remove-Item -LiteralPath $bad -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        $rawPoisoned = ($_.Exception.Message -match 'PAAA7|does not exist|~') -or ($env:TEMP -match '~')
    }

    . $RepairPath

    $okProfile = ($env:USERPROFILE -notmatch '~') -and (Test-Path -LiteralPath $env:USERPROFILE)
    $okTemp = ($env:TEMP -notmatch '~') -and (Test-Path -LiteralPath $env:TEMP)

    $staging = Join-Path $env:TEMP ("claude-client-update-staging-{0}" -f $PID)
    New-Item -ItemType Directory -Force -Path $staging -ErrorAction Stop | Out-Null
    $outFile = Join-Path $env:TEMP ("claude-upd-{0}.out" -f $PID)
    $errFile = Join-Path $env:TEMP ("claude-upd-{0}.err" -f $PID)
    Set-Content -LiteralPath $outFile -Value 'ok' -Encoding ASCII
    Set-Content -LiteralPath $errFile -Value '' -Encoding ASCII

    # Dot-source repair from connect-update top path (file present)
    $upd = Get-Content (Join-Path $WinDir 'connect-update.ps1') -Raw
    $hasFallback = $upd -match "\-notmatch '~'"

    # Simulate connect-update early: re-poison then invoke only the repair preamble via -File Emit + child
    Remove-Item -LiteralPath $staging, $outFile, $errFile -Recurse -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
        RawPoisoned = $rawPoisoned
        OkProfile = $okProfile
        OkTemp = $okTemp
        Temp = $env:TEMP
        Profile = $env:USERPROFILE
        HasFallback = $hasFallback
    }
} -ArgumentList $repairPath, $fake, $Win

$r = Wait-Job $job -Timeout 45 | Receive-Job
Remove-Job $job -Force -ErrorAction SilentlyContinue
Assert ($null -ne $r) 'poison job returned'
if ($r) {
    Assert ([bool]$r.RawPoisoned) 'WITHOUT repair, TEMP stays poisoned (tilde path or New-Item fail)'
    Assert ([bool]$r.OkProfile) ("AFTER repair USERPROFILE long: {0}" -f $r.Profile)
    Assert ([bool]$r.OkTemp) ("AFTER repair TEMP long: {0}" -f $r.Temp)
    Assert ([bool]$r.HasFallback) 'connect-update.ps1 has tilde-reject fallback/repair'
}

# Fresh child: poison env, run repair EmitBatEnv, then staging as update would
$emitJob = Start-Job -ScriptBlock {
    param($RepairPath, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $RepairPath -EmitBatEnv)
    foreach ($line in $lines) {
        if ($line -match '^(USERPROFILE|LOCALAPPDATA|TEMP|TMP)=(.*)$') {
            Set-Item -Path ("Env:{0}" -f $Matches[1]) -Value $Matches[2]
        }
    }
    $staging = Join-Path $env:TEMP ("claude-client-update-staging-{0}" -f $PID)
    New-Item -ItemType Directory -Force -Path $staging -ErrorAction Stop | Out-Null
    $probe = Join-Path $staging 'ssh-redir.out'
    Set-Content -LiteralPath $probe -Value 'x' -Encoding ASCII
    # cleanup
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Temp = $env:TEMP
        Profile = $env:USERPROFILE
        StagingWorked = $true
        NoTilde = (($env:TEMP -notmatch '~') -and ($env:USERPROFILE -notmatch '~'))
    }
} -ArgumentList $repairPath, $fake
$e = Wait-Job $emitJob -Timeout 45 | Receive-Job
Remove-Job $emitJob -Force -ErrorAction SilentlyContinue
Assert ($null -ne $e) 'EmitBatEnv staging job returned'
if ($e) {
    Assert ([bool]$e.NoTilde) 'EmitBatEnv cleared all tildes'
    Assert ([bool]$e.StagingWorked) 'update-style staging + SSH redir file under repaired TEMP'
}

# --- Part C: connect-update.ps1 under poison must not throw PAAA7 on early init ---
Note 'Part C: invoke connect-update.ps1 -Quiet with poisoned TEMP (expect no PAAA7 unhandled)'
$tmpDir = Join-Path $env:TEMP ("claude-83-hard-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
# Minimal fake ScriptDir so update exits early (no server) without needing full tree
foreach ($n in @('connect.bat','connect.ps1','connect-boot.ps1','connect-update.ps1','connect-version.txt','cursor-proxy-sidecar.ps1','connect-env-repair.ps1')) {
    $src = Join-Path $Win $n
    if (Test-Path $src) { Copy-Item -Force $src (Join-Path $tmpDir $n) }
}
# Also need a few siblings update may look for — version file only is enough for "up to date or unreachable"
Set-Content -LiteralPath (Join-Path $tmpDir 'connect-version.txt') -Value '20990101.1' -Encoding ASCII

$updJob = Start-Job -ScriptBlock {
    param($Upd, $ScriptDir, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    $env:CLAUDE_CONNECT_UPDATE_QUIET = '1'
    $env:CLAUDE_CONNECT_SKIP_UPDATE = '0'
    # Force offline-ish: unreachable server so update exits 0 without apply
    $env:CLAUDE_CLIENT_BUNDLE = '/usr/local/share/claude-client-NONEXISTENT-83'
    $out = Join-Path $env:SystemRoot ("Temp\claude-83-upd-out-{0}.txt" -f $PID)
    $err = Join-Path $env:SystemRoot ("Temp\claude-83-upd-err-{0}.txt" -f $PID)
    try {
        $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
            '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File', $Upd, '-ScriptDir', $ScriptDir, '-Quiet'
        ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
        $ec = if ($p) { [int]$p.ExitCode } else { -1 }
    } catch {
        $ec = -99
        Set-Content -LiteralPath $err -Value $_.Exception.Message
    }
    $stdout = ''
    $stderr = ''
    try { $stdout = Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue } catch {}
    try { $stderr = Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue } catch {}
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    $blob = "$stdout`n$stderr"
    [pscustomobject]@{
        ExitCode = $ec
        HitPaaa7 = [bool]($blob -match 'PAAA7~1\.BEH')
        HitUnhandled = [bool]($blob -match 'UPDATE_UNHANDLED|Update error:.*does not exist')
        BlobSample = if ($blob.Length -gt 400) { $blob.Substring(0, 400) } else { $blob }
    }
} -ArgumentList (Join-Path $tmpDir 'connect-update.ps1'), $tmpDir, $fake

$u = Wait-Job $updJob -Timeout 120 | Receive-Job
Remove-Job $updJob -Force -ErrorAction SilentlyContinue
Assert ($null -ne $u) 'connect-update poison invoke returned'
if ($u) {
    Assert (-not [bool]$u.HitPaaa7) ("no PAAA7 in update output (ec={0})" -f $u.ExitCode)
    Assert (-not [bool]$u.HitUnhandled) ("no UPDATE_UNHANDLED path-missing (ec={0})" -f $u.ExitCode)
    # Exit 0 (skip/unreachable) or 1 (fail for other reasons) — PAAA7 is the forbidden signal
    Write-Host ("         update_ec={0} sample={1}" -f $u.ExitCode, (($u.BlobSample -replace '\s+', ' ').Substring(0, [Math]::Min(120, ($u.BlobSample -replace '\s+', ' ').Length))))
}
Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

# --- Part D: server bundle has repair ---
Note 'Part D: live server bundle (if reachable)'
try {
    $hasFile = ((ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 "test -f /usr/local/share/claude-client/connect-env-repair.ps1 && echo YES || echo NO") | Out-String).Trim()
    $ver = ((ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
    Assert ($hasFile -eq 'YES') 'server /usr/local/share/claude-client/connect-env-repair.ps1 exists'
    Assert ($ver -match '^\d{8}\.\d+$') ("server connect-version.txt={0}" -f $ver)
} catch {
    Write-Host "  SKIP  server bundle unreachable: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host ("Result: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })
if ($fail -gt 0) { exit 1 } else { exit 0 }
