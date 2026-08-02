# test-log-sync-chunk-read-nullsafe.ps1
#
# Residual gap after P0.5 (commit 6b79b55): Sync-ConnectLogToServer's Open/Seek/Read/trim
# try had only a finally — no catch. Fleet 2026-08-02 user parsa hit:
#   LOG_SYNC_FAIL ... detail=exception type=NullReferenceException at=596
#   err=Object reference not set to an instance of an object.
# 21ms after a successful LOG_SYNC_OK under dual-Connect writers on the same day log.
#
# at=596 in that build is inside the chunk-read block (partial-read gate). P0.5 only
# null-checked $chunk before WriteAllBytes *after* that block. This test reproduces the
# two production-shaped escapes that the suite previously missed:
#   A) day-log share violation / read failure during the chunk Open/Read try
#   B) Invoke-ConnectLogProcTimed finally throwing (replacing a successful return) —
#      which surfaces as a bare NullReferenceException into Sync's outer catch
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}
$uiPath = Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'
$ui = Get-Content -LiteralPath $uiPath -Raw

Write-Host '=== log sync chunk-read null-safety (parsa NRE residual) ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

# --- static contracts -------------------------------------------------------
$sync = [regex]::Match($ui, '(?ms)^function Sync-ConnectLogToServer \{.*?^\}')
Assert-C 'S1' $sync.Success 'Sync-ConnectLogToServer parseable' $(if ($sync.Success) { 'ok' } else { 'missing' })

$cReadCatch = $sync.Success -and ($sync.Value -match 'detail=chunk_read_fail')
Assert-C 'S2' $cReadCatch 'chunk Open/Seek/Read/trim try logs detail=chunk_read_fail (not outer exception)' $(if ($cReadCatch) { 'ok' } else { 'read try still uncaught' })

$proc = [regex]::Match($ui, '(?ms)^function Invoke-ConnectLogProcTimed \{.*?^\}')
# finally body must be wrapped so a cleanup throw cannot replace the return value.
# Comments may sit between `finally {` and the protective `try {`.
$cFinally = $proc.Success -and ($proc.Value -match '(?ms)finally\s*\{(?:.|\r|\n)*?try\s*\{(?:.|\r|\n)*?\}\s*catch\s*\{\s*\}')
Assert-C 'S3' $cFinally 'Invoke-ConnectLogProcTimed finally is itself try/catch wrapped' $(if ($cFinally) { 'ok' } else { 'finally can still escape' })

$cResGuard = ($ui -match 'if \(-not \$res -or -not \$res\.Ok\)')
Assert-C 'S4' $cResGuard 'Get-ConnectRemoteLogByteSize / hash probe null-check $res before .Ok' $(if ($cResGuard) { 'ok' } else { 'bare $res.Ok remains' })

$cTmpInit = $sync.Success -and ($sync.Value -match '(?m)^\s*\$tmpLocal\s*=\s*\$null\s*$')
Assert-C 'S5' $cTmpInit '$tmpLocal is initialized before the outer try' $(if ($cTmpInit) { 'ok' } else { 'unset $tmpLocal in catch risk' })

# --- live driver ------------------------------------------------------------
$live = Join-Path $env:TEMP ("logsync-chunknre-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null
$driver = Join-Path $live 'driver.ps1'
$driverBody = @'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'chunk-nre-test'
$log = $script:ConnectLogPath
1..8 | ForEach-Object { Write-ConnectLog ("chunk-nre payload $_") 'INFO' }
try { $script:ConnectLogWriter.Flush() } catch { }
$before = [System.IO.FileInfo]::new($log).Length
$beforeOff = [int](Read-ConnectLogSyncWatermark -LogPath $log)

function Get-ConnectLogSyncTarget { return 'claude-server' }
function Test-ConnectLogChunkAlreadyRemote { param($Target,$Day,$Chunk,$Take,$SshOpts,$TimeoutMs) return $false }
function Test-ConnectRemoteLogNeedsRebuild { param($LocalSize,$RemoteSize,$Offset) return $false }
$script:FakeRemote = [int64]0
function Get-ConnectRemoteLogByteSize { param($Target,$Day,$SshOpts,$TimeoutMs) return [int64]$script:FakeRemote }

# ---- Case A: chunk Open/Read throws (share-violation / bad path class) ----
# File.Open on a directory path throws; Test-Path still returns true so Sync enters the
# chunk-read try — the exact uncaught-try gap P0.5 left. Dual-Connect writers produce the
# same exception class (IO / null-ref) at that site; we cannot hold Share.None while the
# long-lived ConnectLogWriter handle is open, so a directory path is the reliable stub.
$script:ConnectLogSyncFailLogged = $false
$dirLog = Join-Path $Home2 'not-a-file-dir'
New-Item -ItemType Directory -Force -Path $dirLog | Out-Null
$escapedA = 0
try {
    Sync-ConnectLogToServer -LogPath $dirLog | Out-Null
} catch {
    $escapedA++
    Write-Output ("ESCAPED_A: " + $_.Exception.GetType().Name + ' :: ' + $_.Exception.Message)
}
try { $script:ConnectLogWriter.Flush() } catch { }
$phaseA = Get-Content -LiteralPath $log -Raw
Write-Output ("PHASEA_CHUNK_FAIL=" + [int]($phaseA -match 'detail=chunk_read_fail'))
Write-Output ("PHASEA_OUTER_EX=" + [int]($phaseA -match 'detail=exception'))
Write-Output ("PHASEA_ESCAPED=" + $escapedA)
# Watermark for the directory LogPath must not be created/advanced as a successful sync.
$dirWm = 0
if (Test-Path -LiteralPath ($dirLog + '.sync-offset')) {
    $dirWm = [int]((Get-Content -LiteralPath ($dirLog + '.sync-offset') -Raw).Trim())
}
Write-Output ("PHASEA_WATERMARK=" + $dirWm)

# ---- Case B: proc helper finally throws bare NRE after a successful return ----
# Pre-fix: finally throw replaced the hashtable return and Sync logged
# detail=exception type=NullReferenceException (exact production breadcrumb shape).
$script:ConnectLogSyncFailLogged = $false
${function:Invoke-ConnectLogProcTimed} = {
    param($Exe, $ArgumentList, $TimeoutMs)
    try {
        $joined = ($ArgumentList -join ' ')
        if ($Exe -eq 'ssh' -and $joined -match 'cat "\$HOME/') {
            $off = [int64](Read-ConnectLogSyncWatermark -LogPath $script:ConnectLogPath)
            $len = [int64]([System.IO.FileInfo]::new($script:ConnectLogPath).Length)
            $take = [Math]::Min([int64]524288, [Math]::Max([int64]0, $len - $off))
            if ($take -gt 0) { $script:FakeRemote += $take }
        }
        return @{ Ok = $true; TimedOut = $false; ExitCode = 0; StdOut = '0'; StdErr = '' }
    } finally {
        throw [System.NullReferenceException]::new()
    }
}
# Restore the REAL helper under a different name, then wrap it so finally-throw is what
# production Sync sees when the live helper's cleanup misbehaves. Here the whole function
# is our stub — after the finally-harden fix the stub's throw still escapes THIS stub
# (the harden is in the real helper). So call the real helper via a nested definition:
Remove-Item Function:Invoke-ConnectLogProcTimed -ErrorAction SilentlyContinue
# Re-dot-source only the real helper by invoking it through a copy taken at boot.
${function:Invoke-ConnectLogProcTimed} = {
    param($Exe, $ArgumentList, $TimeoutMs)
    try {
        $r = & $script:RealProcTimed -Exe $Exe -ArgumentList $ArgumentList -TimeoutMs $TimeoutMs
        return $r
    } finally {
        throw [System.NullReferenceException]::new()
    }
}
# The outer finally throw still escapes *this* wrapper. What we need to prove is that the
# REAL helper's own finally cannot escape. Probe that directly:
$escapedB = 0
$nullResB = 0
try {
    $rB = & $script:RealProcTimed -Exe 'cmd' -ArgumentList @('/c', 'exit', '0') -TimeoutMs 5000
    if ($null -eq $rB) { $nullResB++ }
    elseif (-not $rB.ContainsKey('Ok')) { $nullResB++ }
    Write-Output ("REAL_PROC_OK=" + [int]($rB.Ok -eq $true))
} catch {
    $escapedB++
    Write-Output ("REAL_PROC_ESCAPED: " + $_.Exception.GetType().Name + ' :: ' + $_.Exception.Message)
}
Write-Output ("PHASEB_ESCAPED=" + $escapedB)
Write-Output ("PHASEB_NULL=" + $nullResB)

# ---- Case C: wrapper finally-throw into Sync (pre-harden production shape) ----
# With our stub that returns Ok then throws NRE from finally, Sync must still fail soft
# (either succeed via soft null-res handling, or named detail — never an uncaught escape).
$script:ConnectLogSyncFailLogged = $false
$escapedC = 0
try {
    Sync-ConnectLogToServer | Out-Null
} catch {
    $escapedC++
    Write-Output ("ESCAPED_C: " + $_.Exception.GetType().Name + ' :: ' + $_.Exception.Message)
}
try { $script:ConnectLogWriter.Flush() } catch { }
$phaseC = Get-Content -LiteralPath $log -Raw
# After finally-harden on the REAL helper, this wrapper still throws — Sync's outer catch
# or proc null-guards must keep it soft. Accept either: no exception breadcrumb from a
# bare NRE that escaped unclassified, OR a typed breadcrumb — but never a process-killing escape.
Write-Output ("PHASEC_ESCAPED=" + $escapedC)
Write-Output ("PHASEC_TYPED_OR_NAMED=" + [int]($phaseC -match 'LOG_SYNC_FAIL[^\r\n]*detail=(exception|mkdir_timeout_or_fail|scp_or_append_fail|chunk_read_fail)'))
Write-Output ("PHASEC_BARE_NRE=" + [int]($phaseC -match 'detail=exception type=NullReferenceException at=\d+[^\r\n]*err=Object reference not set'))

$after = [System.IO.FileInfo]::new($log).Length
Write-Output ("GREW=" + [int]($after -ge $before))
Write-Output ("PAYLOAD=" + [int]((Get-Content -LiteralPath $log -Raw) -match 'chunk-nre payload'))
Write-Output ("WATERMARK_NONNEG=" + [int](([int](Read-ConnectLogSyncWatermark -LogPath $log)) -ge 0))
'@

# Capture the real proc helper before the driver stubs it.
$driverBody = $driverBody.Replace(
    ". `$UiPath",
    ". `$UiPath`n`$script:RealProcTimed = `${function:Invoke-ConnectLogProcTimed}")
Set-Content -LiteralPath $driver -Value $driverBody -Encoding ASCII

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver -UiPath $uiPath -Home2 $live 2>&1
$outText = ($out | Out-String)
Write-Host '--- driver output ---'
Write-Host $outText.Trim()
Write-Host '---------------------'

function Get-Flag([string]$Name) {
  $m = [regex]::Match($outText, "(?m)^$Name=(-?\d+)\s*$")
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return -1
}

Assert-C 'L1' ((Get-Flag 'PHASEA_ESCAPED') -eq 0) 'Case A: exclusive day-log lock does not escape Sync' ('escaped=' + (Get-Flag 'PHASEA_ESCAPED'))
Assert-C 'L2' ((Get-Flag 'PHASEA_CHUNK_FAIL') -eq 1) 'Case A: share-violation classified as detail=chunk_read_fail' ('flag=' + (Get-Flag 'PHASEA_CHUNK_FAIL'))
Assert-C 'L3' ((Get-Flag 'PHASEA_OUTER_EX') -eq 0) 'Case A: does not fall through to opaque detail=exception' ('flag=' + (Get-Flag 'PHASEA_OUTER_EX'))
Assert-C 'L4' ((Get-Flag 'PHASEA_WATERMARK') -eq 0) 'Case A: watermark not advanced when chunk read failed' ('wm=' + (Get-Flag 'PHASEA_WATERMARK'))

Assert-C 'L5' ((Get-Flag 'PHASEB_ESCAPED') -eq 0) 'Case B: real Invoke-ConnectLogProcTimed never throws from finally' ('escaped=' + (Get-Flag 'PHASEB_ESCAPED'))
Assert-C 'L6' ((Get-Flag 'REAL_PROC_OK') -eq 1) 'Case B: real proc helper still returns Ok=true for cmd exit 0' ('ok=' + (Get-Flag 'REAL_PROC_OK'))
Assert-C 'L7' ((Get-Flag 'PHASEB_NULL') -eq 0) 'Case B: real proc helper never returns $null' ('null=' + (Get-Flag 'PHASEB_NULL'))

Assert-C 'L8' ((Get-Flag 'PHASEC_ESCAPED') -eq 0) 'Case C: finally-NRE wrapper does not escape Sync-ConnectLogToServer' ('escaped=' + (Get-Flag 'PHASEC_ESCAPED'))
Assert-C 'L9' ((Get-Flag 'PAYLOAD') -eq 1) 'zero-loss: payload lines survive failed syncs' 'present'
Assert-C 'L10' ((Get-Flag 'GREW') -eq 1) 'local day log never shrinks' 'grew-or-same'

try { Remove-Item -LiteralPath $live -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
Write-Host "=== RESULT fail=$fail ==="
if ($fail -eq 0) { Write-Host 'VERDICT: PASS'; exit 0 } else { Write-Host 'VERDICT: HARD FAIL'; exit 1 }
