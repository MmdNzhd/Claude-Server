# test-error-flush-contract.ps1
# Adversarial / fault-injection CONTRACT checks (no live deploy).
# Exit 1 if any contract fails.

$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0
$notes = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool]$Cond, [string]$Name, [string]$Detail = '')
    if ($Cond) {
        Write-Host ("PASS  {0}" -f $Name)
        $script:pass++
    } else {
        Write-Host ("FAIL  {0}" -f $Name) -ForegroundColor Red
        if ($Detail) { Write-Host ("      {0}" -f $Detail) -ForegroundColor DarkYellow }
        $script:fail++
        $script:notes.Add(("HARD FAIL: {0} -- {1}" -f $Name, $Detail))
    }
}

function Get-BalancedBlock {
    param([string]$Text, [string]$StartPattern)
    $m = [regex]::Match($Text, $StartPattern)
    if (-not $m.Success) { return '' }
    $start = $m.Index
    $i = $Text.IndexOf('{', $start)
    if ($i -lt 0) { return '' }
    $depth = 0
    for ($p = $i; $p -lt $Text.Length; $p++) {
        $ch = $Text[$p]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $p - $start + 1)
            }
        }
    }
    return ''
}

$root = (Get-Location).Path
if (-not (Test-Path (Join-Path $root 'scripts\client\windows\connect.ps1'))) {
    # $PSScriptRoot = ...\scripts\client\tests -> repo root is three levels up
    # (tests -> client -> scripts -> root), not two - the two-level version
    # produced ...\scripts\scripts\client\windows\connect.ps1, which never exists,
    # so $root silently stayed as the tests dir (whatever cwd run-all.bat left behind)
    # and every downstream path check failed.
    $cand = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    if (Test-Path (Join-Path $cand 'scripts\client\windows\connect.ps1')) { $root = $cand }
}

$connectPs1 = Join-Path $root 'scripts\client\windows\connect.ps1'
$connectUi  = Join-Path $root 'scripts\client\connect-ui.ps1'
$connectUiSh = Join-Path $root 'scripts\client\connect-ui.sh'
$connectMac = Join-Path $root 'scripts\client\mac\connect.sh'
$updatePs1  = Join-Path $root 'scripts\client\windows\connect-update.ps1'

Write-Host '=== error-flush + WARN coalesce contract ==='
Write-Host ("root={0}" -f $root)
Write-Host ''

Assert-True (Test-Path -LiteralPath $connectPs1) 'connect.ps1 exists' $connectPs1
Assert-True (Test-Path -LiteralPath $connectUi)  'connect-ui.ps1 exists' $connectUi
Assert-True (Test-Path -LiteralPath $updatePs1)  'connect-update.ps1 exists' $updatePs1

$connectRaw = if (Test-Path $connectPs1) { Get-Content -LiteralPath $connectPs1 -Raw } else { '' }
$uiRaw      = if (Test-Path $connectUi)  { Get-Content -LiteralPath $connectUi -Raw } else { '' }
$uiShRaw    = if (Test-Path $connectUiSh) { Get-Content -LiteralPath $connectUiSh -Raw } else { '' }
$macRaw     = if (Test-Path $connectMac) { Get-Content -LiteralPath $connectMac -Raw } else { '' }

# --- 1) Trap logs ERROR before exit ---
$trapBody = Get-BalancedBlock -Text $connectRaw -StartPattern '(?m)^\s*trap\s*'
Assert-True ($trapBody.Length -gt 0) 'trap block parseable' 'no trap { } found in connect.ps1'

$hasWriteLogError = ($trapBody -match 'Write-ConnectLog') -and ($trapBody -match "'ERROR'")
Assert-True $hasWriteLogError 'trap Write-ConnectLog ERROR before exit' 'trap must call Write-ConnectLog ... ERROR before Wait-ConnectExit/exit'

$trapExitsClean = ($trapBody -match 'Wait-ConnectExit') -or ($trapBody -match 'exit\s+\d+')
Assert-True $trapExitsClean 'trap exits via Wait-ConnectExit or exit N' 'silent fall-through forbidden'

$idxLog = $trapBody.IndexOf('Write-ConnectLog')
$idxWait = $trapBody.IndexOf('Wait-ConnectExit')
$orderOk = ($idxLog -ge 0) -and ($idxWait -gt $idxLog)
Assert-True $orderOk 'trap logs ERROR before Wait-ConnectExit' 'log call must precede exit path'

# --- 2) ERROR Force + session-end Force drain ---
$wc = Get-BalancedBlock -Text $uiRaw -StartPattern '(?m)^\s*function Write-ConnectLog\b'
$errorForce = ($wc.Length -gt 0) -and ($wc -match "Level -eq 'ERROR'") -and ($wc -match 'Complete-ConnectLogAsyncDrain\s+-Force')
Assert-True $errorForce 'Write-ConnectLog ERROR triggers Complete-ConnectLogAsyncDrain -Force' 'ERROR must force-flush immediately'

$warnCoalesce = ($wc.Length -gt 0) -and ($wc -match "Level -eq 'WARN'") -and ($wc -match 'ConnectLogWarnPendingUntil') -and ($wc -match 'Request-ConnectLogSync')
Assert-True $warnCoalesce 'Write-ConnectLog WARN coalesces via Request-ConnectLogSync' 'WARN must not per-line Force sync'

$waitBody = Get-BalancedBlock -Text $uiRaw -StartPattern '(?m)^\s*function Wait-ConnectExit\b'
$waitForce = ($waitBody.Length -gt 0) -and ($waitBody -match 'Complete-ConnectLogAsyncDrain\s+-Force')
Assert-True $waitForce 'Wait-ConnectExit calls Complete-ConnectLogAsyncDrain -Force' 'session end must Force drain pending WARN'

$closeBody = Get-BalancedBlock -Text $uiRaw -StartPattern '(?m)^\s*function Close-ConnectLog\b'
$closeForce = ($closeBody.Length -gt 0) -and ($closeBody -match 'Complete-ConnectLogAsyncDrain\s+-Force')
Assert-True $closeForce 'Close-ConnectLog calls Complete-ConnectLogAsyncDrain -Force' 'final close must Force drain'

# --- 3) Watermark / ; true on append ---
$syncBody = Get-BalancedBlock -Text $uiRaw -StartPattern '(?m)^\s*function Sync-ConnectLogToServer\b'
Assert-True ($syncBody.Length -gt 0) 'Sync-ConnectLogToServer parseable' ''

$offsetOnlyOnSuccess = $false
$catHasTrue = $false
$watermarkDoc = New-Object System.Collections.Generic.List[string]
if ($syncBody.Length -gt 0) {
    $sb = $syncBody
    $offsetOnlyOnSuccess = ($sb -match 'if\s*\(\s*\$scpOk\s*\)') -and ($sb -match 'ConnectLogSyncOffset\s*=\s*\$off\s*\+\s*\$take')
    $catLines = @($sb -split "`n" | Where-Object { $_ -match '\$cat\s*=' })
    if ($catLines.Count -gt 0) {
        $catLine = $catLines[0].Trim()
        $catHasTrue = ($catLine -match ';\s*true')
        $watermarkDoc.Add(("cat line: {0}" -f $catLine))
    }
    $watermarkDoc.Add(("offset advance gated by scpOk: {0}" -f $offsetOnlyOnSuccess))
    $watermarkDoc.Add(("cat contains '; true' (masks append fail): {0}" -f $catHasTrue))
}

Assert-True $offsetOnlyOnSuccess 'watermark advances only inside if ($scpOk)' 'offset must not bump on mkdir/scp/cat failure'
Assert-True (-not $catHasTrue) 'no ; true in log append ssh remote cmd' 'trailing ; true => watermark ADVANCES on failed append'

# --- 4) Mac ERR trap flush ---
$macErrFlush = ($macRaw -match "trap 'ec=\$\?") -and ($macRaw -match 'flush_connect_log_to_server')
Assert-True $macErrFlush 'Mac ERR/EXIT trap calls flush_connect_log_to_server' 'ERR trap must Force-drain via flush_connect_log_to_server'

$macFlushBody = Get-BalancedBlock -Text $uiShRaw -StartPattern '(?m)^flush_connect_log_to_server\(\)'
$macFlushForce = ($macFlushBody.Length -gt 0) -and ($macFlushBody -match 'complete_connect_log_async_drain force')
Assert-True $macFlushForce 'Mac flush_connect_log_to_server uses complete_connect_log_async_drain force' 'session-end must Force drain coalesced WARN'

# --- 5) connect-update ERROR must not exit 0 ---
$updateErrorExit0 = New-Object System.Collections.Generic.List[string]
$updateErrorExitNonzero = New-Object System.Collections.Generic.List[string]
$updateLines = if (Test-Path $updatePs1) { Get-Content -LiteralPath $updatePs1 } else { @() }
for ($i = 0; $i -lt $updateLines.Count; $i++) {
    $line = $updateLines[$i]
    if ($line -notmatch "'ERROR'") { continue }
    if ($line -match 'exit\s+(\d+)') {
        $code = [int]$Matches[1]
        $entry = ("{0}:{1}" -f ($i + 1), $line.Trim())
        if ($code -eq 0) { [void]$updateErrorExit0.Add($entry) } else { [void]$updateErrorExitNonzero.Add($entry) }
        continue
    }
    for ($j = 1; $j -le 4 -and ($i + $j) -lt $updateLines.Count; $j++) {
        if ($updateLines[$i + $j] -match 'exit\s+(\d+)') {
            $code = [int]$Matches[1]
            $entry = ("{0}->{1}:{2}" -f ($i + 1), ($i + $j + 1), $updateLines[$i + $j].Trim())
            if ($code -eq 0) { [void]$updateErrorExit0.Add($entry) } else { [void]$updateErrorExitNonzero.Add($entry) }
            break
        }
    }
}

Assert-True ($updateErrorExit0.Count -eq 0) 'connect-update ERROR paths must not exit 0' (("found {0}: {1}" -f $updateErrorExit0.Count, (($updateErrorExit0 | Select-Object -First 6) -join ' | ')))
Assert-True ($updateErrorExitNonzero.Count -gt 0) 'connect-update has exit 1/nonzero near ERROR' 'Select-String found no ERROR+exit nonzero pairing'

# --- Summary ---
Write-Host ''
Write-Host '=== WATERMARK (code read) ==='
foreach ($w in $watermarkDoc) { Write-Host ("  {0}" -f $w) }
Write-Host ''
Write-Host ("=== RESULT pass={0} fail={1} ===" -f $pass, $fail)
if ($fail -gt 0) {
    Write-Host 'CONTRACT FAILED' -ForegroundColor Red
    foreach ($n in $notes) { Write-Host ("  - {0}" -f $n) -ForegroundColor DarkYellow }
    exit 1
}
Write-Host 'CONTRACT OK' -ForegroundColor Green
exit 0
