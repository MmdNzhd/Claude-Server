$ErrorActionPreference = 'Stop'
$p = 'scripts/client/connect-ui.ps1'
$t = [IO.File]::ReadAllText($p)

function Replace-Once([string]$Text, [string]$Old, [string]$New) {
    if ($Text.Contains($New)) { return $Text }
    $idx = $Text.IndexOf($Old)
    if ($idx -lt 0) { throw "missing marker length=$($Old.Length)" }
    return $Text.Substring(0, $idx) + $New + $Text.Substring($idx + $Old.Length)
}

$t = Replace-Once $t `
    '$mkResRb = Invoke-ConnectLogProcTimed -Exe ''ssh'' -ArgumentList ($sshOpts + @($target, $mk)) -TimeoutMs 12000' `
    '$mkRb = ''mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true''`r`n            $mkResRb = Invoke-ConnectLogProcTimed -Exe ''ssh'' -ArgumentList ($sshOpts + @($target, $mkRb)) -TimeoutMs 12000'

$oldTimer = "                    if (-not `$needed -and -not `$warnActive) { return }`r`n                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {`r`n                        Sync-ConnectLogToServer | Out-Null`r`n                    }`r`n                    if (`$script:ConnectLogWarnPendingUntil -and (Get-Date) -ge `$script:ConnectLogWarnPendingUntil) {`r`n                        `$script:ConnectLogWarnPendingUntil = `$null`r`n                    }"
$newTimer = "                    if (-not `$needed -and -not `$warnActive) { return }`r`n                    `$unsynced = [int64]0`r`n                    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {`r`n                        `$unsynced = Get-ConnectLogUnsyncedByteCount`r`n                    }`r`n                    if (`$unsynced -gt 262144) {`r`n                        if (-not `$script:ConnectLogAsyncStallSince) { `$script:ConnectLogAsyncStallSince = Get-Date }`r`n                        elseif (((Get-Date) - `$script:ConnectLogAsyncStallSince).TotalSeconds -ge 120) {`r`n                            if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {`r`n                                Sync-ConnectLogToServer -Force | Out-Null`r`n                            }`r`n                            `$script:ConnectLogAsyncStallSince = `$null`r`n                            if (-not `$script:ConnectLogSyncNeeded -and -not `$script:ConnectLogWarnPendingUntil) { return }`r`n                        }`r`n                    } else { `$script:ConnectLogAsyncStallSince = `$null }`r`n                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {`r`n                        Sync-ConnectLogToServer | Out-Null`r`n                    }`r`n                    if (`$script:ConnectLogWarnPendingUntil -and (Get-Date) -ge `$script:ConnectLogWarnPendingUntil) {`r`n                        `$script:ConnectLogWarnPendingUntil = `$null`r`n                    }"
$t = Replace-Once $t $oldTimer $newTimer

$oldReq = "    `$alreadyNeeded = [bool]`$script:ConnectLogSyncNeeded`r`n    `$script:ConnectLogSyncNeeded = `$true`r`n    Ensure-ConnectLogAsyncTimer`r`n    if (-not `$alreadyNeeded -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {`r`n        try { Write-ConnectLog 'LOG_SYNC_ASYNC scheduled=1' 'DEBUG' } catch { }`r`n    }"
$newReq = "    `$alreadyNeeded = [bool]`$script:ConnectLogSyncNeeded`r`n    `$script:ConnectLogSyncNeeded = `$true`r`n    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {`r`n        `$u = Get-ConnectLogUnsyncedByteCount`r`n        if (`$u -gt 262144 -and -not `$script:ConnectLogAsyncStallSince) { `$script:ConnectLogAsyncStallSince = Get-Date }`r`n        elseif (`$u -le 262144) { `$script:ConnectLogAsyncStallSince = `$null }`r`n    }`r`n    Ensure-ConnectLogAsyncTimer`r`n    if (-not `$alreadyNeeded -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {`r`n        try { Write-ConnectLog 'LOG_SYNC_ASYNC scheduled=1' 'DEBUG' } catch { }`r`n    }"
$t = Replace-Once $t $oldReq $newReq

[IO.File]::WriteAllText($p, $t)
if ($t -notmatch 'mkRb = ''mkdir') { throw 'mk patch failed' }
if ($t -notmatch 'ConnectLogAsyncStallSince\).TotalSeconds') { throw 'timer patch failed' }
Write-Host 'PATCH2 OK'
