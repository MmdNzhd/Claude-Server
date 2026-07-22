$ErrorActionPreference = 'Stop'
$OLD = '20260721.56'
$NEW = '20260721.57'
$ps1Path = 'scripts/client/connect-ui.ps1'
$shPath = 'scripts/client/connect-ui.sh'

function Replace-Once([string]$Text, [string]$Old, [string]$New) {
    if ($Text.Contains($New)) { return $Text }
    $idx = $Text.IndexOf($Old)
    if ($idx -lt 0) { Write-Host "SKIP missing: $($Old.Substring(0, [Math]::Min(60, $Old.Length)))..."; return $Text }
    Write-Host "OK replace: $($Old.Substring(0, [Math]::Min(60, $Old.Length)))..."
    return $Text.Substring(0, $idx) + $New + $Text.Substring($idx + $Old.Length)
}

$ps1 = [IO.File]::ReadAllText($ps1Path)
$sh = [IO.File]::ReadAllText($shPath)

$marker = 'function Test-ConnectLogChunkAlreadyRemote {'
$helpers = @'
function Test-ConnectRemoteLogNeedsRebuild {
    param(
        [int64]$LocalSize,
        [int64]$RemoteSize,
        [int]$Offset
    )
    if ($RemoteSize -lt 0) { return $false }
    if ($Offset -eq 0 -and $RemoteSize -gt $LocalSize) { return $true }
    if ($LocalSize -gt 0 -and $RemoteSize -gt ($LocalSize * 2)) { return $true }
    if ($RemoteSize -gt ($LocalSize + 1048576)) { return $true }
    return $false
}

function Get-ConnectLogUnsyncedByteCount {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath)) { return [int64]0 }
    try {
        $off = [int64](Read-ConnectLogSyncWatermark -LogPath $LogPath)
        $len = [int64]([System.IO.FileInfo]::new($LogPath).Length)
        if ($off -lt 0) { $off = 0 }
        if ($off -gt $len) { return $len }
        return ($len - $off)
    } catch { return [int64]0 }
}

function Test-ConnectLogChunkAlreadyRemote {
'@
$ps1 = Replace-Once $ps1 $marker $helpers

$ps1 = Replace-Once $ps1 '$script:ConnectLogAsyncTimerSubId = $null' "`$script:ConnectLogAsyncTimerSubId = `$null`r`n`$script:ConnectLogAsyncStallSince = `$null"
$ps1 = Replace-Once $ps1 "`$script:ConnectLogAsyncDrainerRunning = `$false`r`n    try {" "`$script:ConnectLogAsyncDrainerRunning = `$false`r`n    `$script:ConnectLogAsyncStallSince = `$null`r`n    try {"
$ps1 = Replace-Once $ps1 '    if ($script:ConnectLogSyncInProgress -and -not $Force) { return }' "    if (`$script:ConnectLogSyncInProgress -and -not `$Force) {`r`n        if (-not `$LogPath -or `$LogPath -eq `$script:ConnectLogPath) { `$script:ConnectLogSyncNeeded = `$true }`r`n        return`r`n    }"
$ps1 = Replace-Once $ps1 "    } catch {`r`n        if (-not `$Force) { return }" "    } catch {`r`n        if (-not `$Force) {`r`n            if (-not `$LogPath -or `$LogPath -eq `$script:ConnectLogPath) { `$script:ConnectLogSyncNeeded = `$true }`r`n            return`r`n        }"

$oldRec = '        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---'
$newRec = @'
        $remoteBeforeProbe = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
        if ($remoteBeforeProbe -lt 0) { $remoteBeforeProbe = [int64]0 }
        if (Test-ConnectRemoteLogNeedsRebuild -LocalSize $fileLen -RemoteSize $remoteBeforeProbe -Offset $off) {
            Clear-ConnectLogSyncPending -LogPath $path
            $replace = 'cat "$HOME/' + $remoteTmp + '" > "$HOME/' + $remoteDay + '"; ec=$?; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; exit $ec'
            $mkResRb = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $mk)) -TimeoutMs 12000
            if ($mkResRb.Ok) {
                $scpFull = Invoke-ConnectLogProcTimed -Exe 'scp' -ArgumentList (@('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-q', $path, "${target}:$remoteTmp")) -TimeoutMs 60000
                if ($scpFull.Ok) {
                    $repRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $replace)) -TimeoutMs 20000
                    if ($repRes.Ok) {
                        Write-ConnectLogSyncWatermark -Offset $fileLen -LogPath $path
                        if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                            $script:ConnectLogSyncOffset = [int]$fileLen
                            $script:ConnectLogLinesSinceSync = 0
                            $script:ConnectLogSyncNeeded = $false
                            $script:ConnectLogAsyncStallSince = $null
                        }
                        $script:LastConnectLogSyncOk = $true
                        $script:ConnectLogSyncFailLogged = $false
                        try {
                            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                            $sid = Get-ConnectSessionId
                            if ($script:ConnectLogWriter) {
                                $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_REBUILD local=$fileLen remote_was=$remoteBeforeProbe off=$off (replaced remote day log)")
                            }
                        } catch { }
                        try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
                        return
                    }
                }
            }
        }
        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---
'@
$ps1 = Replace-Once $ps1 $oldRec $newRec

$oldTimer = @'
                    if (-not $needed -and -not $warnActive) { return }
                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                        Sync-ConnectLogToServer | Out-Null
                    }
                    if ($script:ConnectLogWarnPendingUntil -and (Get-Date) -ge $script:ConnectLogWarnPendingUntil) {
'@
$newTimer = @'
                    if (-not $needed -and -not $warnActive) { return }
                    $unsynced = [int64]0
                    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
                        $unsynced = Get-ConnectLogUnsyncedByteCount
                    }
                    if ($unsynced -gt 262144) {
                        if (-not $script:ConnectLogAsyncStallSince) { $script:ConnectLogAsyncStallSince = Get-Date }
                        elseif (((Get-Date) - $script:ConnectLogAsyncStallSince).TotalSeconds -ge 120) {
                            if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                                Sync-ConnectLogToServer -Force | Out-Null
                            }
                            $script:ConnectLogAsyncStallSince = $null
                            if (-not $script:ConnectLogSyncNeeded -and -not $script:ConnectLogWarnPendingUntil) { return }
                        }
                    } else { $script:ConnectLogAsyncStallSince = $null }
                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                        Sync-ConnectLogToServer | Out-Null
                    }
                    if ($script:ConnectLogWarnPendingUntil -and (Get-Date) -ge $script:ConnectLogWarnPendingUntil) {
'@
$ps1 = Replace-Once $ps1 $oldTimer $newTimer

$oldReq = @'
    $alreadyNeeded = [bool]$script:ConnectLogSyncNeeded
    $script:ConnectLogSyncNeeded = $true
    Ensure-ConnectLogAsyncTimer
    if (-not $alreadyNeeded -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {
'@
$newReq = @'
    $alreadyNeeded = [bool]$script:ConnectLogSyncNeeded
    $script:ConnectLogSyncNeeded = $true
    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
        $u = Get-ConnectLogUnsyncedByteCount
        if ($u -gt 262144 -and -not $script:ConnectLogAsyncStallSince) { $script:ConnectLogAsyncStallSince = Get-Date }
        elseif ($u -le 262144) { $script:ConnectLogAsyncStallSince = $null }
    }
    Ensure-ConnectLogAsyncTimer
    if (-not $alreadyNeeded -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {
'@
$ps1 = Replace-Once $ps1 $oldReq $newReq

[IO.File]::WriteAllText($ps1Path, $ps1)
Write-Host 'connect-ui.ps1 done'

# shell parity
$sh = Replace-Once $sh '_server_logs_cleanup_cmd() {' @'
test_connect_remote_log_needs_rebuild() {
    local local_size="$1" remote_size="$2" offset="$3"
    [ -z "$remote_size" ] && remote_size=0
    [ -z "$local_size" ] && local_size=0
    [ -z "$offset" ] && offset=0
    if [ "$offset" -eq 0 ] && [ "$remote_size" -gt "$local_size" ] 2>/dev/null; then return 0; fi
    if [ "$local_size" -gt 0 ] && [ "$remote_size" -gt $((local_size * 2)) ] 2>/dev/null; then return 0; fi
    if [ "$remote_size" -gt $((local_size + 1048576)) ] 2>/dev/null; then return 0; fi
    return 1
}

_connect_log_unsynced_bytes() {
    local lp="${CONNECT_LOG_PATH:-}" off=0 sz=0
    [ -n "$lp" ] && [ -f "$lp" ] || { printf '0'; return 0; }
    if [ -f "${lp}.sync-offset" ]; then
        off="$(tr -dc '0-9' < "${lp}.sync-offset")"
    fi
    : "${off:=0}"
    sz="$(wc -c < "$lp" | tr -dc '0-9')"
    : "${sz:=0}"
    if [ "$off" -gt "$sz" ] 2>/dev/null; then printf '%s' "$sz"; return 0; fi
    printf '%s' $((sz - off))
}

_server_logs_cleanup_cmd() {
'@

$sh = Replace-Once $sh 'CONNECT_LOG_DRAINER_PID=""' "CONNECT_LOG_DRAINER_PID=`"`"`nCONNECT_LOG_ASYNC_STALL_SINCE=0"
$sh = Replace-Once $sh "    CONNECT_LOG_DRAINER_PID=`"`"`n    project=" "    CONNECT_LOG_DRAINER_PID=`"`"`n    CONNECT_LOG_ASYNC_STALL_SINCE=0`n    project="

$sh = Replace-Once $sh @'
    CONNECT_LOG_SYNC_NEEDED=1
    if [ "$already_needed" != "1" ] && declare -F connect_log >/dev/null 2>&1; then
'@ @'
    CONNECT_LOG_SYNC_NEEDED=1
    if declare -F _connect_log_unsynced_bytes >/dev/null 2>&1; then
        unsynced="$(_connect_log_unsynced_bytes)"
        if [ "${unsynced:-0}" -gt 262144 ] 2>/dev/null; then
            if [ "${CONNECT_LOG_ASYNC_STALL_SINCE:-0}" -eq 0 ] 2>/dev/null; then
                CONNECT_LOG_ASYNC_STALL_SINCE="$(date +%s)"
            fi
        else
            CONNECT_LOG_ASYNC_STALL_SINCE=0
        fi
    fi
    if [ "$already_needed" != "1" ] && declare -F connect_log >/dev/null 2>&1; then
'@

$sh = Replace-Once $sh @'
        sync_connect_log_to_server || true
        sleep 1.5
    done
'@ @'
        if declare -F _connect_log_unsynced_bytes >/dev/null 2>&1; then
            unsynced="$(_connect_log_unsynced_bytes)"
            if [ "${unsynced:-0}" -gt 262144 ] 2>/dev/null; then
                if [ "${CONNECT_LOG_ASYNC_STALL_SINCE:-0}" -eq 0 ] 2>/dev/null; then
                    CONNECT_LOG_ASYNC_STALL_SINCE="$(date +%s)"
                elif [ "$(($(date +%s) - CONNECT_LOG_ASYNC_STALL_SINCE))" -ge 120 ] 2>/dev/null; then
                    sync_connect_log_to_server force || true
                    CONNECT_LOG_ASYNC_STALL_SINCE=0
                    sleep 1.5
                    continue
                fi
            else
                CONNECT_LOG_ASYNC_STALL_SINCE=0
            fi
        fi
        sync_connect_log_to_server || true
        sleep 1.5
    done
'@

$sh = Replace-Once $sh '        flock -n 8 || return 0' '        flock -n 8 || { CONNECT_LOG_SYNC_NEEDED=1; return 0; }'

$oldRecSh = '    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---'
$newRecSh = @'
    remote_before=0
    if declare -F sshx >/dev/null 2>&1; then
        remote_before="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    else
        remote_before="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    fi
    : "${remote_before:=0}"
    if declare -F test_connect_remote_log_needs_rebuild >/dev/null 2>&1 && test_connect_remote_log_needs_rebuild "$size" "$remote_before" "$off"; then
        rm -f "${CONNECT_LOG_PATH}.sync-pending" "${CONNECT_LOG_PATH}.chunk" 2>/dev/null || true
        if declare -F sshx >/dev/null 2>&1; then
            sshx "$(_server_logs_cleanup_cmd)" >/dev/null 2>&1 || true
        fi
        if scp -o BatchMode=yes -o ConnectTimeout=20 -q "$CONNECT_LOG_PATH" "${ALIAS}:${remote_tmp}" 2>/dev/null; then
            rep_ok=0
            if declare -F sshx >/dev/null 2>&1; then
                if sshx "cat \"\$HOME/${remote_tmp}\" > \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1; then
                    rep_ok=1
                fi
            else
                if ssh -o BatchMode=yes -o ConnectTimeout=12 "$ALIAS" "cat \"\$HOME/${remote_tmp}\" > \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1; then
                    rep_ok=1
                fi
            fi
            if [ "$rep_ok" = 1 ]; then
                CONNECT_LOG_SYNC_OFF="$size"
                printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
                CONNECT_LOG_LINES_SINCE_SYNC=0
                CONNECT_LOG_SYNC_NEEDED=0
                CONNECT_LOG_ASYNC_STALL_SINCE=0
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "LOG_SYNC_REBUILD local=$size remote_was=$remote_before off=$off (replaced remote day log)" 'INFO'
                fi
                flock -u 8 2>/dev/null || true
                return 0
            fi
        fi
    fi

    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---
'@
$sh = Replace-Once $sh $oldRecSh $newRecSh

[IO.File]::WriteAllText($shPath, $sh)
Write-Host 'connect-ui.sh done'

foreach ($rel in @('scripts/client/windows/connect.ps1','scripts/client/mac/connect.sh','scripts/client/windows/connect-version.txt','scripts/client/mac/connect-version.txt')) {
    $t = [IO.File]::ReadAllText($rel).Replace($OLD, $NEW)
    [IO.File]::WriteAllText($rel, $t)
    Write-Host "version $rel"
}

$policyPath = 'scripts/server/client-update-policy.json'
$policy = [regex]::Replace([IO.File]::ReadAllText($policyPath), '"force_min_version":\s*"[^"]+"', ('"force_min_version": "' + $NEW + '"'))
[IO.File]::WriteAllText($policyPath, $policy)
Write-Host 'policy done'

$testPath = 'scripts/client/tests/test-git-mode-deep.ps1'
$tt = [IO.File]::ReadAllText($testPath)
if ($tt -notmatch 'LOG_SYNC_REBUILD') {
    $tt = $tt.Replace("Assert (`$cuiPs -match 'mtime \\+1') 'connect-ui.ps1 deletes server logs older than 1 day'", "Assert (`$cuiPs -match 'LOG_SYNC_REBUILD') 'connect-ui.ps1 rebuilds bloated remote day logs'`r`nAssert (`$cuiPs -match 'mtime \\+1') 'connect-ui.ps1 deletes server logs older than 1 day'")
    $tt = $tt.Replace("    Assert (`$cuiSh -match 'mtime \\+1') 'connect-ui.sh deletes server logs older than 1 day'", "    Assert (`$cuiSh -match 'LOG_SYNC_REBUILD') 'connect-ui.sh rebuilds bloated remote day logs'`r`n    Assert (`$cuiSh -match 'mtime \\+1') 'connect-ui.sh deletes server logs older than 1 day'")
    [IO.File]::WriteAllText($testPath, $tt)
    Write-Host 'tests done'
}

if ($ps1 -notmatch 'LOG_SYNC_REBUILD') { throw 'ps1 patch incomplete' }
if ($sh -notmatch 'LOG_SYNC_REBUILD') { throw 'sh patch incomplete' }
Write-Host 'PATCH OK'
