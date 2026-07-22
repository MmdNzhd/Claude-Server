#!/usr/bin/env python3
"""Patch connect-ui.ps1/sh for LOG_SYNC_REBUILD + stall recovery. One-shot."""
import re
from pathlib import Path

ROOT = Path('scripts/client')
PS1 = ROOT / 'connect-ui.ps1'
SH = ROOT / 'connect-ui.sh'
OLD_VER = '20260721.56'
NEW_VER = '20260721.57'

ps1 = PS1.read_text(encoding='utf-8')
sh = SH.read_text(encoding='utf-8')

# --- PS1: add helpers after Get-ConnectRemoteLogByteSize ---
marker_ps1 = '''function Test-ConnectLogChunkAlreadyRemote {'''
helpers_ps1 = '''function Test-ConnectRemoteLogNeedsRebuild {
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

function Test-ConnectLogChunkAlreadyRemote {'''
if 'function Test-ConnectRemoteLogNeedsRebuild' not in ps1:
    if marker_ps1 not in ps1:
        raise SystemExit('PS1 marker missing for helpers')
    ps1 = ps1.replace(marker_ps1, helpers_ps1, 1)

# --- PS1: init stall tracker ---
ps1 = ps1.replace(
    '$script:ConnectLogAsyncTimerSubId = $null',
    '$script:ConnectLogAsyncTimerSubId = $null\n$script:ConnectLogAsyncStallSince = $null',
    1,
)
ps1 = ps1.replace(
    '    $script:ConnectLogAsyncDrainerRunning = $false\n    try {',
    '    $script:ConnectLogAsyncDrainerRunning = $false\n    $script:ConnectLogAsyncStallSince = $null\n    try {',
    1,
)

# --- PS1: fix silent lock returns ---
ps1 = ps1.replace(
    '    if ($script:ConnectLogSyncInProgress -and -not $Force) { return }',
    '    if ($script:ConnectLogSyncInProgress -and -not $Force) {\n        if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) { $script:ConnectLogSyncNeeded = $true }\n        return\n    }',
    1,
)
ps1 = ps1.replace(
    '    } catch {\n        if (-not $Force) { return }',
    '    } catch {\n        if (-not $Force) {\n            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) { $script:ConnectLogSyncNeeded = $true }\n            return\n        }',
    1,
)

# --- PS1: rebuild block before pending reconcile ---
rebuild_block_ps1 = '''        $remoteBeforeProbe = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
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
        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---'''
old_reconcile = '        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---'
if 'LOG_SYNC_REBUILD local=' not in ps1:
    if old_reconcile not in ps1:
        raise SystemExit('PS1 reconcile marker missing')
    ps1 = ps1.replace(old_reconcile, rebuild_block_ps1, 1)

# --- PS1: timer stall force ---
old_timer = '''                    if (-not $needed -and -not $warnActive) { return }
                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                        Sync-ConnectLogToServer | Out-Null
                    }'''
new_timer = '''                    if (-not $needed -and -not $warnActive) { return }
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
                    }'''
if 'ConnectLogAsyncStallSince).TotalSeconds' not in ps1:
    if old_timer not in ps1:
        raise SystemExit('PS1 timer block missing')
    ps1 = ps1.replace(old_timer, new_timer, 1)

# --- PS1: Request-ConnectLogSync stall seed ---
old_req = '''    $alreadyNeeded = [bool]$script:ConnectLogSyncNeeded
    $script:ConnectLogSyncNeeded = $true
    Ensure-ConnectLogAsyncTimer'''
new_req = '''    $alreadyNeeded = [bool]$script:ConnectLogSyncNeeded
    $script:ConnectLogSyncNeeded = $true
    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
        $u = Get-ConnectLogUnsyncedByteCount
        if ($u -gt 262144 -and -not $script:ConnectLogAsyncStallSince) { $script:ConnectLogAsyncStallSince = Get-Date }
        elseif ($u -le 262144) { $script:ConnectLogAsyncStallSince = $null }
    }
    Ensure-ConnectLogAsyncTimer'''
if 'ConnectLogAsyncStallSince = Get-Date' not in ps1.split('function Request-ConnectLogSync')[1].split('function Complete-ConnectLogAsyncDrain')[0]:
    if old_req not in ps1:
        raise SystemExit('PS1 Request-ConnectLogSync block missing')
    ps1 = ps1.replace(old_req, new_req, 1)

PS1.write_text(ps1, encoding='utf-8', newline='\r\n')
print('patched connect-ui.ps1')

# --- SH helpers ---
if 'test_connect_remote_log_needs_rebuild()' not in sh:
    sh = sh.replace(
        '_server_logs_cleanup_cmd() {',
        '''test_connect_remote_log_needs_rebuild() {
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

_server_logs_cleanup_cmd() {''',
        1,
    )

# SH stall vars
if 'CONNECT_LOG_ASYNC_STALL_SINCE=' not in sh:
    sh = sh.replace(
        'CONNECT_LOG_DRAINER_PID=""',
        'CONNECT_LOG_DRAINER_PID=""\nCONNECT_LOG_ASYNC_STALL_SINCE=0',
        1,
    )
    sh = sh.replace(
        '    CONNECT_LOG_DRAINER_PID=""\n    project=',
        '    CONNECT_LOG_DRAINER_PID=""\n    CONNECT_LOG_ASYNC_STALL_SINCE=0\n    project=',
        1,
    )

# SH request_connect_log_sync stall seed
old_req_sh = '''    CONNECT_LOG_SYNC_NEEDED=1
    if [ "$already_needed" != "1" ] && declare -F connect_log >/dev/null 2>&1; then'''
new_req_sh = '''    CONNECT_LOG_SYNC_NEEDED=1
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
    if [ "$already_needed" != "1" ] && declare -F connect_log >/dev/null 2>&1; then'''
if 'CONNECT_LOG_ASYNC_STALL_SINCE="$(date +%s)"' not in sh.split('request_connect_log_sync()')[1].split('complete_connect_log_async_drain()')[0]:
    sh = sh.replace(old_req_sh, new_req_sh, 1)

# SH drainer loop stall force
old_loop = '''        sync_connect_log_to_server || true
        sleep 1.5'''
new_loop = '''        if declare -F _connect_log_unsynced_bytes >/dev/null 2>&1; then
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
        sleep 1.5'''
if 'CONNECT_LOG_ASYNC_STALL_SINCE="$(date +%s)"' not in sh.split('_connect_log_async_drainer_loop()')[1].split('_ensure_connect_log_async_drainer()')[0]:
    sh = sh.replace(old_loop, new_loop, 1)

# SH lock silent return -> keep needed
sh = sh.replace(
    '        flock -n 8 || return 0',
    '        flock -n 8 || { CONNECT_LOG_SYNC_NEEDED=1; return 0; }',
    1,
)

# SH rebuild block
rebuild_sh = '''    remote_before=0
    if declare -F sshx >/dev/null 2>&1; then
        remote_before="$(sshx "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    else
        remote_before="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
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
                if sshx "cat \\"\\$HOME/${remote_tmp}\\" > \\"\\$HOME/${remote_day}\\"; ec=\\$?; rm -f \\"\\$HOME/${remote_tmp}\\"; chmod 600 \\"\\$HOME/${remote_day}\\" 2>/dev/null; exit \\$ec" >/dev/null 2>&1; then
                    rep_ok=1
                fi
            else
                if ssh -o BatchMode=yes -o ConnectTimeout=12 "$ALIAS" "cat \\"\\$HOME/${remote_tmp}\\" > \\"\\$HOME/${remote_day}\\"; ec=\\$?; rm -f \\"\\$HOME/${remote_tmp}\\"; chmod 600 \\"\\$HOME/${remote_day}\\" 2>/dev/null; exit \\$ec" >/dev/null 2>&1; then
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

    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---'''
old_rec_sh = '    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---'
if 'LOG_SYNC_REBUILD local=' not in sh:
    sh = sh.replace(old_rec_sh, rebuild_sh, 1)

SH.write_text(sh, encoding='utf-8', newline='\n')
print('patched connect-ui.sh')

# version bumps
for rel in [
    'scripts/client/windows/connect.ps1',
    'scripts/client/mac/connect.sh',
    'scripts/client/windows/connect-version.txt',
    'scripts/client/mac/connect-version.txt',
    'scripts/server/client-update-policy.json',
]:
    p = Path(rel)
    t = p.read_text(encoding='utf-8')
    if rel.endswith('client-update-policy.json'):
        t = re.sub(r'"force_min_version":\s*"[^"]+"', f'"force_min_version": "{NEW_VER}"', t)
    else:
        t = t.replace(OLD_VER, NEW_VER)
    nl = '\r\n' if rel.endswith('.ps1') or rel.endswith('.txt') and 'windows' in rel else '\n'
    if rel.endswith('.ps1'):
        nl = '\r\n'
    p.write_text(t, encoding='utf-8', newline=nl)
    print('updated', rel)

# test assert
test = Path('scripts/client/tests/test-git-mode-deep.ps1')
tt = test.read_text(encoding='utf-8')
if 'LOG_SYNC_REBUILD' not in tt:
    tt = tt.replace(
        "Assert ($cuiPs -match 'mtime \\+1') 'connect-ui.ps1 deletes server logs older than 1 day'",
        "Assert ($cuiPs -match 'LOG_SYNC_REBUILD') 'connect-ui.ps1 rebuilds bloated remote day logs'\nAssert ($cuiPs -match 'mtime \\+1') 'connect-ui.ps1 deletes server logs older than 1 day'",
        1,
    )
    tt = tt.replace(
        "    Assert ($cuiSh -match 'mtime \\+1') 'connect-ui.sh deletes server logs older than 1 day'",
        "    Assert ($cuiSh -match 'LOG_SYNC_REBUILD') 'connect-ui.sh rebuilds bloated remote day logs'\n    Assert ($cuiSh -match 'mtime \\+1') 'connect-ui.sh deletes server logs older than 1 day'",
        1,
    )
    test.write_text(tt, encoding='utf-8', newline='\r\n')
    print('updated test-git-mode-deep.ps1')

print('DONE')
