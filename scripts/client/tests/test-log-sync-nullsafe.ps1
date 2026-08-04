# test-log-sync-nullsafe.ps1 - log sync must fail soft, never with a null-ref.
#
# Field report: "LOG_SYNC_FAIL target=claude-server detail=exception err=Object reference not
# set to an instance of an object." Invoke-ConnectLogProcTimed was the only call inside
# Sync-ConnectLogToServer that was not internally fail-soft, so anything it threw (a null from
# Process.Start, a Kill/WaitForExit race, or the missing Format-ProcessArgumentString helper
# when connect-ui.ps1 is dot-sourced standalone) aborted the whole sync mid-flight.
#
# Contract: every sync failure degrades to a named detail= breadcrumb, the local day log and
# its watermark survive untouched (zero-loss), and no exception escapes.
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

Write-Host '=== log sync null-safety contracts ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

# --- static contracts -------------------------------------------------------
$proc = [regex]::Match($ui, '(?ms)^function Invoke-ConnectLogProcTimed \{.*?^\}')
Assert-C '1' $proc.Success 'Invoke-ConnectLogProcTimed parseable' $(if ($proc.Success) { 'ok' } else { 'not found' })

$c2 = $proc.Success -and ($proc.Value -match '(?m)^\s*\}\s*catch\s*\{') -and ($proc.Value -match 'Ok = \$false')
Assert-C '2' $c2 'proc helper has a catch that returns a failure result' $(if ($c2) { 'ok' } else { 'helper can still throw into the sync path' })

$c3 = $proc.Value -match 'if \(-not \$p\)'
Assert-C '3' $c3 'Process.Start null return is guarded before deref' $(if ($c3) { 'ok' } else { 'unguarded $p deref' })

$c4 = $ui -match 'function Format-ConnectLogProcArguments'
Assert-C '4' $c4 'arg formatting is self-contained (no editor-launch.ps1 dependency)' $(if ($c4) { 'ok' } else { 'missing fallback' })

# Every result of the proc helper must be null-checked before .Ok is read.
$bare = [regex]::Matches($ui, '(?m)(?<![-\w$])\$(mkRes|mkResRb|scpRes|scpFull|repRes|catRes|scp2|cat2)\.Ok')
$guarded = $true
foreach ($m in $bare) {
  $line = $ui.Substring(0, $m.Index)
  $lineStart = $line.LastIndexOfAny([char[]]@("`n", "`r")) + 1
  $text = $ui.Substring($lineStart, ($m.Index - $lineStart) + $m.Length)
  if ($text -notmatch '\$' + $m.Groups[1].Value + '\s+-and' -and $text -notmatch '-not \$' + $m.Groups[1].Value + '\s+-or') { $guarded = $false; Write-Host "      unguarded: $text" }
}
Assert-C '5' $guarded 'every proc result is null-checked before .Ok' $(if ($guarded) { 'ok' } else { 'see unguarded lines above' })

$c6 = ($ui -match 'LOG_SYNC_FAIL target=\{0\} detail=\{1\} type=\{2\} at=\{3\}') -or ($ui -match 'LOG_SYNC_FAIL target=\{0\} detail=exception type=\{1\} at=\{2\}')
Assert-C '6' $c6 'exception breadcrumb carries type= and at= (throw site)' $(if ($c6) { 'ok' } else { 'opaque breadcrumb' })

$c6b = $ui -match 'function Write-ConnectLogSyncFailBreadcrumb' -and ($ui -match 'AppendAllText') -and ($ui -match 'detailKind = ''chunk_read_fail''')
Assert-C '6b' $c6b 'fail breadcrumb helper + chunk-line reclassify present' $(if ($c6b) { 'ok' } else { 'missing helper/reclassify' })

# --- live: drive the real function with connect-ui.ps1 dot-sourced ALONE ----
$live = Join-Path $env:TEMP ("logsync-nullsafe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null
$driver = Join-Path $live 'driver.ps1'
$driverBody = @'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
# Deliberately NOT dot-sourcing editor-launch.ps1: designer/connect-design load connect-ui.ps1
# on its own, and log sync must still work there.
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'nullsafe-test'
$log = $script:ConnectLogPath
Write-ConnectLog 'payload line that must survive every failed sync' 'INFO'
try { $script:ConnectLogWriter.Flush() } catch { }
$before = [System.IO.FileInfo]::new($log).Length

$escaped = 0
$nullResults = 0
function Invoke-ConnectLogProcTimed {
    param($Exe, $ArgumentList, $TimeoutMs)
    switch ($script:StubMode) {
        'null'    { return $null }
        'throw'   { throw [System.NullReferenceException]::new() }
        'timeout' { return @{ Ok = $false; TimedOut = $true; ExitCode = -1; StdOut = ''; StdErr = '' } }
        'nonzero' { return @{ Ok = $false; TimedOut = $false; ExitCode = 255; StdOut = ''; StdErr = 'denied' } }
        default   { return @{ StdOut = '' } }
    }
}
function Invoke-SyncModes([string[]]$Modes) {
    foreach ($mode in $Modes) {
        Set-Variable -Name StubMode -Value $mode -Scope Script
        foreach ($force in @($false, $true)) {
            $script:ConnectLogSyncFailLogged = $false
            try {
                if ($force) { Sync-ConnectLogToServer -Force | Out-Null } else { Sync-ConnectLogToServer | Out-Null }
            } catch {
                $script:escaped++
                Write-Output ("ESCAPED[$mode force=$force]: " + $_.Exception.GetType().Name + ' :: ' + $_.Exception.Message)
            }
        }
    }
}

# Phase 1: failure shapes production code can actually hand back. None of them may reach the
# generic exception handler - each must be classified into a named detail=.
Invoke-SyncModes @('null', 'timeout', 'nonzero', 'missing-key')
try { $script:ConnectLogWriter.Flush() } catch { }
$phase1 = Get-Content -LiteralPath $script:ConnectLogPath -Raw
Write-Output ("PHASE1_EXCEPTION=" + [int]($phase1 -match 'detail=exception'))
Write-Output ("PHASE1_REASON=" + [int]($phase1 -match 'detail=(mkdir_timeout_or_fail|scp_or_append_fail) rc='))

# Phase 2: a genuine null-ref from below must still fail soft, and the breadcrumb must name
# its own throw site instead of just "Object reference not set to an instance of an object."
Invoke-SyncModes @('throw')
try { $script:ConnectLogWriter.Flush() } catch { }
$phase2 = Get-Content -LiteralPath $script:ConnectLogPath -Raw
# at= may be "123" or "connect-ui.ps1:123" after the script-name breadcrumb upgrade.
Write-Output ("PHASE2_TYPED=" + [int]($phase2 -match 'detail=exception type=NullReferenceException at=\S*[1-9]\d*'))

# The real helper must also never throw / never return $null, even with no arg formatter.
foreach ($spec in @(@('cmd', @('/c', 'exit', '0'), 3000), @('no-such-exe-xyz', @('a'), 1000), @('cmd', @('/c', 'exit', '1'), 1))) {
    try {
        $r = Invoke-ConnectLogProcTimedReal -Exe $spec[0] -ArgumentList $spec[1] -TimeoutMs $spec[2]
        if ($null -eq $r) { $nullResults++; Write-Output ("NULLRESULT: " + $spec[0]) }
        elseif (-not $r.ContainsKey('Ok')) { $nullResults++; Write-Output ("BADSHAPE: " + $spec[0]) }
    } catch {
        $escaped++
        Write-Output ("HELPER ESCAPED[" + $spec[0] + "]: " + $_.Exception.GetType().Name + ' :: ' + $_.Exception.Message)
    }
}

try { $script:ConnectLogWriter.Flush() } catch { }
$after = [System.IO.FileInfo]::new($log).Length
$watermark = 0
$wp = $log + '.sync-offset'
if (Test-Path -LiteralPath $wp) { $watermark = [int]((Get-Content -LiteralPath $wp -Raw).Trim()) }
$body = Get-Content -LiteralPath $log -Raw

Write-Output ("ESCAPED=$escaped")
Write-Output ("NULLRESULTS=$nullResults")
Write-Output ("GREW=" + [int]($after -ge $before))
Write-Output ("PAYLOAD=" + [int]($body -match 'payload line that must survive'))
Write-Output ("WATERMARK=$watermark")
Write-Output ("SOFTFAIL_LOGGED=" + [int]($body -match 'LOG_SYNC_FAIL[^\r\n]*detail='))
'@
# Keep a handle on the production helper before the stubs shadow it.
$driverBody = $driverBody.Replace(". `$UiPath", ". `$UiPath`n`${function:Invoke-ConnectLogProcTimedReal} = `${function:Invoke-ConnectLogProcTimed}")
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

$escaped = Get-Flag 'ESCAPED'
Assert-C '7' ($escaped -eq 0) 'no exception escapes Sync-ConnectLogToServer under any proc failure' "escaped=$escaped"

$nullRes = Get-Flag 'NULLRESULTS'
Assert-C '8' ($nullRes -eq 0) 'real proc helper never returns $null / malformed result' "bad=$nullRes"

Assert-C '9' ((Get-Flag 'PAYLOAD') -eq 1) 'zero-loss: local day log still holds the payload after failed syncs' 'payload present'

Assert-C '10' ((Get-Flag 'GREW') -eq 1) 'local day log never shrinks across failed syncs' 'len(after) >= len(before)'

Assert-C '11' ((Get-Flag 'WATERMARK') -eq 0) 'watermark not advanced when the remote append never succeeded' ('watermark=' + (Get-Flag 'WATERMARK'))

Assert-C '12' ((Get-Flag 'PHASE1_EXCEPTION') -eq 0) 'realistic proc failures never reach detail=exception (the reported regression)' 'all classified into named detail='

Assert-C '13' ((Get-Flag 'PHASE2_TYPED') -eq 1) 'a real null-ref still fails soft and names type= + at=' 'typed breadcrumb'

Assert-C '14' ((Get-Flag 'SOFTFAIL_LOGGED') -eq 1) 'failures still leave a durable LOG_SYNC_FAIL detail= breadcrumb' 'present'

Assert-C '15' ((Get-Flag 'PHASE1_REASON') -eq 1) 'mkdir/scp breadcrumbs carry rc= so a repeat failure says why' 'rc= present'

try { Remove-Item -LiteralPath $live -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
Write-Host "=== RESULT fail=$fail ==="
if ($fail -eq 0) { Write-Host 'VERDICT: PASS'; exit 0 } else { Write-Host 'VERDICT: HARD FAIL'; exit 1 }
