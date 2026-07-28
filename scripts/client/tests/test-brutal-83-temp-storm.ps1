# test-brutal-83-temp-storm.ps1
# BRUTAL: harder than hardest — no repair file, parallel poison, bootstrap/heal/auth/logsync,
# bat emit, server xray verify gap, and connect-update inline-fallback-only.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Win = Join-Path $RepoRoot 'scripts\client\windows'
$Client = Join-Path $RepoRoot 'scripts\client'
$pass = 0; $fail = 0; $skip = 0
function Assert([bool]$c, [string]$m) {
    if ($c) { $script:pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
}
function Note([string]$m) { Write-Host "  ----  $m" -ForegroundColor DarkCyan }
function SoftSkip([string]$m) { $script:skip++; Write-Host "  SKIP  $m" -ForegroundColor DarkYellow }

$fake = 'C:\Users\PAAA7~1.BEH'
$sysTemp = Join-Path $env:SystemRoot 'Temp'

Write-Host '=== BRUTAL 8.3 / Parsa storm ===' -ForegroundColor Magenta

# ---------- 0) Cleanup accidental literal poison ----------
if (Test-Path -LiteralPath $fake) {
    Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------- 1) Inline-fallback-only: connect-update WITHOUT connect-env-repair.ps1 ----------
Note '1) connect-update inline fallback (NO connect-env-repair.ps1 in ScriptDir)'
$fix1 = Join-Path $sysTemp ("brutal-83-nofile-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $fix1 | Out-Null
foreach ($n in @('connect.bat','connect.ps1','connect-boot.ps1','connect-update.ps1','connect-version.txt','cursor-proxy-sidecar.ps1')) {
    Copy-Item -Force (Join-Path $Win $n) (Join-Path $fix1 $n)
}
# Explicitly ensure repair is ABSENT
Remove-Item -LiteralPath (Join-Path $fix1 'connect-env-repair.ps1') -Force -ErrorAction SilentlyContinue
Assert (-not (Test-Path (Join-Path $fix1 'connect-env-repair.ps1'))) 'fixture has NO connect-env-repair.ps1'
Set-Content -LiteralPath (Join-Path $fix1 'connect-version.txt') -Value '20990101.1' -Encoding ASCII

$j1 = Start-Job -ScriptBlock {
    param($Upd, $Dir, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    $env:CLAUDE_CONNECT_UPDATE_QUIET = '1'
    $env:CLAUDE_CLIENT_BUNDLE = '/usr/local/share/claude-client-NONEXISTENT-BRUTAL'
    $out = Join-Path $env:SystemRoot ("Temp\brutal-upd-out-{0}.txt" -f $PID)
    $err = Join-Path $env:SystemRoot ("Temp\brutal-upd-err-{0}.txt" -f $PID)
    $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$Upd,'-ScriptDir',$Dir,'-Quiet'
    ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    $blob = ''
    try { $blob += (Get-Content $out -Raw -EA SilentlyContinue) } catch {}
    try { $blob += "`n" + (Get-Content $err -Raw -EA SilentlyContinue) } catch {}
    Remove-Item $out,$err -Force -EA SilentlyContinue
    [pscustomobject]@{
        Ec = $(if ($p) { [int]$p.ExitCode } else { -1 })
        Hit = [bool]($blob -match 'PAAA7~1\.BEH|UPDATE_UNHANDLED|does not exist')
    }
} -ArgumentList (Join-Path $fix1 'connect-update.ps1'), $fix1, $fake
$r1 = Wait-Job $j1 -Timeout 90 | Receive-Job
Remove-Job $j1 -Force -EA SilentlyContinue
Assert ($null -ne $r1) 'nofile update job returned'
if ($r1) {
    Assert (-not [bool]$r1.Hit) ("inline-fallback update: no PAAA7/UNHANDLED (ec={0})" -f $r1.Ec)
}
Remove-Item -LiteralPath $fix1 -Recurse -Force -EA SilentlyContinue

# ---------- 2) bootstrap/heal must have INLINE fallback when repair file missing ----------
Note '2) bootstrap/heal inline fallback contract (not file-only)'
$boot = Get-Content (Join-Path $Win 'connect-bootstrap.ps1') -Raw
$heal = Get-Content (Join-Path $Win 'connect-heal.ps1') -Raw
# Either full inline tilde-reject OR a function that repairs without requiring the file to exist forever
$bootHasInline = ($boot -match "\-notmatch '~'") -and ($boot -match 'GetFolderPath\(''UserProfile''\)|Repair-ConnectWindowsProfileTempEnv')
$healHasInline = ($heal -match "\-notmatch '~'") -and ($heal -match 'GetFolderPath\(''UserProfile''\)|Repair-ConnectWindowsProfileTempEnv')
# Current design: only dotsource if file exists — BRUTAL requires else-inline like connect-update
Assert ($boot -match 'if \(Test-Path -LiteralPath \$_connectEnvRepair\)') 'bootstrap tries repair file'
Assert ($heal -match 'if \(Test-Path -LiteralPath \$_connectEnvRepair\)') 'heal tries repair file'
Assert ($bootHasInline -or ($boot -match '(?s)if \(Test-Path[^\)]+\)\s*\{\s*\. \$_connectEnvRepair\s*\}\s*else\s*\{')) 'bootstrap has else-inline repair when file missing'
Assert ($healHasInline -or ($heal -match '(?s)if \(Test-Path[^\)]+\)\s*\{\s*\. \$_connectEnvRepair\s*\}\s*else\s*\{')) 'heal has else-inline repair when file missing'

# ---------- 3) Live: bootstrap entry under poison WITHOUT repair sibling ----------
Note '3) live bootstrap preamble under poison without repair file'
$fix3 = Join-Path $sysTemp ("brutal-83-boot-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $fix3 | Out-Null
Copy-Item -Force (Join-Path $Win 'connect-bootstrap.ps1') (Join-Path $fix3 'connect-bootstrap.ps1')
# no repair file
$j3 = Start-Job -ScriptBlock {
    param($BootPs1, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    # Dot-source only the header by running a snippet: parse + execute repair block via running script until Canon set
    # Safer: invoke script with -Here that fails network quickly, capture whether TEMP cleaned
    $out = Join-Path $env:SystemRoot ("Temp\brutal-boot-out-{0}.txt" -f $PID)
    $err = Join-Path $env:SystemRoot ("Temp\brutal-boot-err-{0}.txt" -f $PID)
    $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$BootPs1,'-Here',$Fake,'-Quiet'
    ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    # After process, we cannot see child env. Instead probe: did it try New-Item under PAAA7?
    $blob = ''
    try { $blob += (Get-Content $out -Raw -EA SilentlyContinue) } catch {}
    try { $blob += "`n" + (Get-Content $err -Raw -EA SilentlyContinue) } catch {}
    Remove-Item $out,$err -Force -EA SilentlyContinue
    $hit = [bool]($blob -match 'PAAA7~1\.BEH does not exist')
    [pscustomobject]@{ Ec = $(if($p){[int]$p.ExitCode}else{-1}); HitPaaa7 = $hit; Sample = if($blob.Length-gt200){$blob.Substring(0,200)}else{$blob} }
} -ArgumentList (Join-Path $fix3 'connect-bootstrap.ps1'), $fake
$r3 = Wait-Job $j3 -Timeout 60 | Receive-Job
Remove-Job $j3 -Force -EA SilentlyContinue
Assert ($null -ne $r3) 'bootstrap poison job returned'
if ($r3) {
    Assert (-not [bool]$r3.HitPaaa7) ("bootstrap without repair file: no PAAA7 path error (ec={0})" -f $r3.Ec)
}
Remove-Item -LiteralPath $fix3 -Recurse -Force -EA SilentlyContinue

# ---------- 4) Parallel storm: 8x repair+staging ----------
Note '4) parallel x8 poison->repair->staging'
$jobs = @()
1..8 | ForEach-Object {
    $jobs += Start-Job -ScriptBlock {
        param($RepairPath, $Fake, $i)
        $env:USERPROFILE = $Fake
        $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
        $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
        $env:TMP = $env:TEMP
        . $RepairPath
        if ($env:TEMP -match '~') { return "fail_tilde_$i" }
        $d = Join-Path $env:TEMP ("brutal-stage-$i-$PID")
        New-Item -ItemType Directory -Force -Path $d -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'x.out') -Value 'ok'
        Remove-Item -LiteralPath $d -Recurse -Force
        "ok_$i"
    } -ArgumentList (Join-Path $Win 'connect-env-repair.ps1'), $fake, $_
}
$null = Wait-Job $jobs -Timeout 60
$outs = $jobs | ForEach-Object { Receive-Job $_; Remove-Job $_ -Force -EA SilentlyContinue }
$okN = @($outs | Where-Object { $_ -match '^ok_' }).Count
Assert ($okN -eq 8) ("parallel storm 8/8 ok (got {0}: {1})" -f $okN, ($outs -join ','))

# ---------- 5) Get-CursorAuthTempRoot under poison ----------
Note '5) Get-CursorAuthTempRoot rejects poison'
$j5 = Start-Job -ScriptBlock {
    param($AuthPath, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    # Extract and run only the function
    $raw = Get-Content -LiteralPath $AuthPath -Raw
    $m = [regex]::Match($raw, '(?s)function Get-CursorAuthTempRoot\s*\{.*?^\}\s*(?=function |\z)', [Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $m.Success) { return @{ Ok = $false; Why = 'extract_fail' } }
    Invoke-Expression $m.Value
    $t = Get-CursorAuthTempRoot
    @{ Ok = ($t -and ($t -notmatch '~') -and (Test-Path -LiteralPath $t)); Temp = $t }
} -ArgumentList (Join-Path $Client 'cursor-auth-laptop.ps1'), $fake
$r5 = Wait-Job $j5 -Timeout 30 | Receive-Job
Remove-Job $j5 -Force -EA SilentlyContinue
Assert ($null -ne $r5) 'auth temp job returned'
if ($r5) {
    Assert ([bool]$r5.Ok) ("Get-CursorAuthTempRoot long path: {0}" -f $r5.Temp)
}

# ---------- 6) logsync-style New-Item + cleanup under repaired env ----------
Note '6) logsync TEMP files after repair (TEMP_CLEANUP_FAIL class)'
$j6 = Start-Job -ScriptBlock {
    param($RepairPath, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    . $RepairPath
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outFile = Join-Path $env:TEMP ("claude-logsync-$id.out")
    $errFile = Join-Path $env:TEMP ("claude-logsync-$id.err")
    Set-Content -LiteralPath $outFile -Value 'x' -Encoding ASCII
    Set-Content -LiteralPath $errFile -Value '' -Encoding ASCII
    $cleanupFail = $false
    foreach ($f in @($outFile, $errFile)) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop }
        catch { $cleanupFail = $true }
    }
    @{
        TempOk = ($env:TEMP -notmatch '~')
        CleanupFail = $cleanupFail
        HadTildePath = ($outFile -match '~')
    }
} -ArgumentList (Join-Path $Win 'connect-env-repair.ps1'), $fake
$r6 = Wait-Job $j6 -Timeout 30 | Receive-Job
Remove-Job $j6 -Force -EA SilentlyContinue
Assert ($null -ne $r6) 'logsync job returned'
if ($r6) {
    Assert ([bool]$r6.TempOk) 'logsync TEMP repaired'
    Assert (-not [bool]$r6.HadTildePath) 'logsync paths have no tilde'
    Assert (-not [bool]$r6.CleanupFail) 'logsync Remove-Item no TEMP_CLEANUP_FAIL'
}

# ---------- 7) bat EmitBatEnv under poison (child process) ----------
Note '7) connect-env-repair -EmitBatEnv under poison'
$j7 = Start-Job -ScriptBlock {
    param($RepairPath, $Fake)
    $env:USERPROFILE = $Fake
    $env:LOCALAPPDATA = Join-Path $Fake 'AppData\Local'
    $env:TEMP = Join-Path $Fake 'AppData\Local\Temp'
    $env:TMP = $env:TEMP
    $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $RepairPath -EmitBatEnv)
    $text = $lines -join "`n"
    @{
        Ok = ($text -match '(?m)^USERPROFILE=') -and ($text -match '(?m)^TEMP=') -and ($text -notmatch '~')
        Text = $text
    }
} -ArgumentList (Join-Path $Win 'connect-env-repair.ps1'), $fake
$r7 = Wait-Job $j7 -Timeout 30 | Receive-Job
Remove-Job $j7 -Force -EA SilentlyContinue
Assert ($null -ne $r7) 'EmitBatEnv job returned'
if ($r7) { Assert ([bool]$r7.Ok) 'EmitBatEnv under poison emits long paths only' }

# ---------- 8) setup-launch/worker source repair ----------
Note '8) setup-launch/worker repair dotsource'
$launch = Get-Content (Join-Path $RepoRoot 'publish\_setup-launch-body.ps1') -Raw
$worker = Get-Content (Join-Path $RepoRoot 'publish\_setup-worker-body.ps1') -Raw
Assert ($launch -match 'connect-env-repair') 'setup-launch dotsources repair'
Assert ($worker -match 'connect-env-repair') 'setup-worker dotsources repair'

# ---------- 9) xray fleet: live + verify must mention xray ----------
Note '9) live xray + verify.sh must check xray (fleet blast radius)'
try {
    $xr = ((ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "systemctl is-active xray; ss -tln | grep -cE '10808|10809' || true; curl -sS -x socks5h://127.0.0.1:10808 -o /dev/null -w '%{http_code}' --connect-timeout 6 https://api2.cursor.sh/ || echo FAIL") | Out-String).Trim()
    Assert ($xr -match 'active') ("xray active: {0}" -f $xr)
    Assert ($xr -match '200') ("xray proxy http 200: {0}" -f $xr)
} catch {
    SoftSkip ("xray live unreachable: {0}" -f $_.Exception.Message)
}
$verify = Get-Content (Join-Path $RepoRoot 'scripts\server\commands\verify.sh') -Raw -EA SilentlyContinue
if ($verify) {
    Assert ($verify -match '10808|xray') 'claude-server verify checks xray/10808 (else fleet dies silent)'
} else {
    SoftSkip 'verify.sh missing'
}

# Probe cache TTL must not be huge silent sticky — assert documented bound
$gm = Get-Content (Join-Path $Client 'git-mode.ps1') -Raw
Assert ($gm -match '1800|xray-probe-cache|ForceProbe') 'git-mode has xray probe cache / ForceProbe knobs'

# ---------- 10) connect.ps1 inline fallback without repair file ----------
Note '10) connect.ps1 early repair without repair file (parse + poison child)'
$fix10 = Join-Path $sysTemp ("brutal-83-ps1-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $fix10 | Out-Null
# Minimal stubs so connect.ps1 can load far enough — too heavy. Instead assert source has else-inline.
$ps1 = Get-Content (Join-Path $Win 'connect.ps1') -Raw
Assert ($ps1 -match '(?s)if \(Test-Path -LiteralPath \$_connectEnvRepair\).*else\s*\{') 'connect.ps1 has else-inline repair'
Assert ($ps1 -match "\-notmatch '~'") 'connect.ps1 rejects tilde in inline repair'
Remove-Item -LiteralPath $fix10 -Recurse -Force -EA SilentlyContinue

# ---------- 11) Server bundle .38+ has heal/bootstrap with repair in lists ----------
Note '11) server bundle heal/bootstrap pull lists'
try {
    $remote = ((ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "grep -c connect-env-repair /usr/local/share/claude-client/connect-heal.ps1; grep -c connect-env-repair /usr/local/share/claude-client/connect-bootstrap.ps1; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") | Out-String).Trim()
    $lines = $remote -split '\r?\n'
    Assert ([int]$lines[0] -gt 0) ("server heal mentions repair count={0}" -f $lines[0])
    Assert ([int]$lines[1] -gt 0) ("server bootstrap mentions repair count={0}" -f $lines[1])
    Assert ($lines[2] -match '^\d{8}\.\d+$') ("server ver={0}" -f $lines[2])
} catch {
    SoftSkip ("server bundle check: {0}" -f $_.Exception.Message)
}

Write-Host ''
Write-Host ("BRUTAL Result: {0} passed, {1} failed, {2} skipped" -f $pass, $fail, $skip) -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })
if ($fail -gt 0) { exit 1 } else { exit 0 }
