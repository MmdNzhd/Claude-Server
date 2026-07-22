# -*- coding: utf-8 -*-
"""Task A: log-sync dedupe reconcile. Task B: batch SSH / skip redundant trips."""
from pathlib import Path
import re

ROOT = Path('.')

def parse_ok(ps1_path: Path):
    # deferred - run via powershell separately
    pass

# ---------------------------------------------------------------------------
# Task A helpers to insert into connect-ui.ps1 after Write-ConnectLogSyncWatermark
# ---------------------------------------------------------------------------
HELPERS = r'''
function Get-ConnectLogSyncPendingPath {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath) { $LogPath = Get-ConnectLogDayPath }
    return ($LogPath + '.sync-pending')
}

function Clear-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (Test-Path -LiteralPath $pp) { Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Write-ConnectLogSyncPending {
    param(
        [int]$Offset,
        [int]$Take,
        [int64]$RemoteBefore,
        [string]$LogPath = $script:ConnectLogPath
    )
    try {
        $line = '{0}|{1}|{2}' -f $Offset, $Take, $RemoteBefore
        Set-Content -LiteralPath (Get-ConnectLogSyncPendingPath -LogPath $LogPath) -Value $line -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
    } catch { }
}

function Read-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (-not (Test-Path -LiteralPath $pp)) { return $null }
        $raw = ((Get-Content -LiteralPath $pp -Raw -ErrorAction SilentlyContinue) + '').Trim()
        if ($raw -notmatch '^(\d+)\|(\d+)\|(\d+)$') { return $null }
        return [PSCustomObject]@{
            Offset       = [int]$Matches[1]
            Take         = [int]$Matches[2]
            RemoteBefore = [int64]$Matches[3]
        }
    } catch { return $null }
}

function Get-ConnectRemoteLogByteSize {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [string[]]$SshOpts
    )
    # Lightweight: one ssh. Returns 0 if missing/unreadable.
    $cmd = 'stat -c%s "$HOME/.claude/logs/connect-' + $Day + '.log" 2>/dev/null || echo 0'
    $res = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList (@($SshOpts) + @($Target, $cmd)) -TimeoutMs 8000
    if (-not $res.Ok) { return [int64](-1) }
    # Read stdout from a fresh ssh (Invoke-ConnectLogProcTimed discards stdout) - use & ssh directly with short timeout.
    try {
        $raw = (& ssh @SshOpts $Target $cmd 2>$null | Out-String).Trim()
        $n = 0L
        if ([int64]::TryParse(($raw -replace '[^0-9]', ''), [ref]$n)) { return $n }
    } catch { }
    return [int64](-1)
}

function Test-ConnectLogChunkAlreadyRemote {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [Parameter(Mandatory)][byte[]]$Chunk,
        [Parameter(Mandatory)][int]$Take,
        [string[]]$SshOpts
    )
    if ($Take -le 0 -or $Take -gt 524288) { return $false }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $localHash = ([BitConverter]::ToString($sha.ComputeHash($Chunk))).Replace('-', '').ToLowerInvariant()
        $sha.Dispose()
    } catch { return $false }
    $cmd = 'f="$HOME/.claude/logs/connect-' + $Day + '.log"; if [ ! -f "$f" ]; then echo none; exit 0; fi; sz=$(stat -c%s "$f" 2>/dev/null || echo 0); if [ "$sz" -lt ' + $Take + ' ]; then echo short; exit 0; fi; tail -c ' + $Take + ' "$f" | sha256sum | awk ''{print $1}'''
    try {
        $raw = ((& ssh @SshOpts $Target $cmd 2>$null) | Out-String).Trim().ToLowerInvariant()
        $remoteHash = ($raw -replace '[^0-9a-f]', '')
        if ($remoteHash.Length -ge 64) { $remoteHash = $remoteHash.Substring(0, 64) }
        return ($remoteHash -eq $localHash)
    } catch { return $false }
}

'''

# Note: Get-ConnectRemoteLogByteSize above calls Invoke-ConnectLogProcTimed which is defined LATER.
# Helpers that call Invoke-ConnectLogProcTimed must be placed AFTER that function, OR we only use & ssh.
# Fix: simplify Get-ConnectRemoteLogByteSize to only use & ssh (no Invoke-ConnectLogProcTimed).

HELPERS = r'''
function Get-ConnectLogSyncPendingPath {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath) { $LogPath = Get-ConnectLogDayPath }
    return ($LogPath + '.sync-pending')
}

function Clear-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (Test-Path -LiteralPath $pp) { Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Write-ConnectLogSyncPending {
    param(
        [int]$Offset,
        [int]$Take,
        [int64]$RemoteBefore,
        [string]$LogPath = $script:ConnectLogPath
    )
    try {
        $line = '{0}|{1}|{2}' -f $Offset, $Take, $RemoteBefore
        Set-Content -LiteralPath (Get-ConnectLogSyncPendingPath -LogPath $LogPath) -Value $line -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
    } catch { }
}

function Read-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (-not (Test-Path -LiteralPath $pp)) { return $null }
        $raw = ((Get-Content -LiteralPath $pp -Raw -ErrorAction SilentlyContinue) + '').Trim()
        if ($raw -notmatch '^(\d+)\|(\d+)\|(\d+)$') { return $null }
        return [PSCustomObject]@{
            Offset       = [int]$Matches[1]
            Take         = [int]$Matches[2]
            RemoteBefore = [int64]$Matches[3]
        }
    } catch { return $null }
}

function Get-ConnectRemoteLogByteSize {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [string[]]$SshOpts
    )
    # Lightweight remote size probe. -1 = probe failed (do not treat as reconcile success).
    $cmd = 'stat -c%s "$HOME/.claude/logs/connect-' + $Day + '.log" 2>/dev/null || echo 0'
    try {
        $raw = (& ssh @SshOpts -o ConnectTimeout=6 $Target $cmd 2>$null | Out-String).Trim()
        $digits = ($raw -replace '[^0-9]', '')
        if (-not $digits) { return [int64](-1) }
        return [int64]$digits
    } catch {
        return [int64](-1)
    }
}

function Test-ConnectLogChunkAlreadyRemote {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [Parameter(Mandatory)][byte[]]$Chunk,
        [Parameter(Mandatory)][int]$Take,
        [string[]]$SshOpts
    )
    # Idempotency: if remote tail bytes match the chunk we are about to send, skip append.
    if ($Take -le 0 -or $Take -gt 524288) { return $false }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $localHash = ([BitConverter]::ToString($sha.ComputeHash($Chunk))).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
    } catch { return $false }
    $cmd = 'f="$HOME/.claude/logs/connect-' + $Day + '.log"; if [ ! -f "$f" ]; then echo none; exit 0; fi; sz=$(stat -c%s "$f" 2>/dev/null || echo 0); if [ "$sz" -lt ' + $Take + ' ]; then echo short; exit 0; fi; tail -c ' + $Take + ' "$f" | sha256sum | awk ''{print $1}'''
    try {
        $raw = ((& ssh @SshOpts -o ConnectTimeout=8 $Target $cmd 2>$null) | Out-String).Trim().ToLowerInvariant()
        $remoteHash = ($raw -replace '[^0-9a-f]', '')
        if ($remoteHash.Length -ge 64) { $remoteHash = $remoteHash.Substring(0, 64) }
        return ($remoteHash -eq $localHash)
    } catch { return $false }
}

'''

def patch_connect_ui_ps1():
    p = ROOT / 'scripts/client/connect-ui.ps1'
    t = p.read_text(encoding='utf-8')
    if 'Test-ConnectLogChunkAlreadyRemote' in t:
        print('connect-ui.ps1: helpers already present')
    else:
        anchor = 'function Write-ConnectLogSyncWatermark {\n    param([int]$Offset, [string]$LogPath = $script:ConnectLogPath)\n    try {\n        Set-Content -LiteralPath (Get-ConnectLogSyncWatermarkPath -LogPath $LogPath) -Value "$Offset" -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue\n    } catch { }\n}\n'
        if anchor not in t:
            raise SystemExit('Write-ConnectLogSyncWatermark anchor not found')
        t = t.replace(anchor, anchor + '\n' + HELPERS, 1)
        print('connect-ui.ps1: inserted helpers')

    # Patch Sync-ConnectLogToServer: after day/remote paths computed and before mk, insert reconcile.
    # Find the block starting with $mk = 'mkdir
    marker = "        $mk = 'mkdir -p \"$HOME/.claude/logs\""
    if 'LOG_SYNC_RECONCILE' in t:
        print('connect-ui.ps1: reconcile already present')
    else:
        if marker not in t:
            raise SystemExit('mk marker not found')
        reconcile = r'''        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        $pending = Read-ConnectLogSyncPending -LogPath $path
        if ($pending -and $pending.Offset -eq $off -and $pending.Take -eq $take) {
            $rNow = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
            if ($rNow -ge 0 -and $rNow -ge ($pending.RemoteBefore + [int64]$pending.Take)) {
                $newOff = $off + $take
                Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
                Clear-ConnectLogSyncPending -LogPath $path
                if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                    $script:ConnectLogSyncOffset = $newOff
                    $script:ConnectLogLinesSinceSync = 0
                    if ($newOff -lt $fileLen) { $script:ConnectLogLinesSinceSync = 25 }
                }
                $script:LastConnectLogSyncOk = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE pending_ok off=$off take=$take remote=$rNow (skipped re-append)")
                    }
                } catch { }
                if ($Force -and $newOff -lt $fileLen) {
                    # Fall through into Force drain by pretending first chunk already synced:
                    # re-enter via recursive Force after return would re-lock; instead jump by
                    # resetting $off/$take for remaining bytes below after skipping scp.
                } else {
                    try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
                    return
                }
            }
        }
        if (Test-ConnectLogChunkAlreadyRemote -Target $target -Day $day -Chunk $chunk -Take $take -SshOpts $sshOpts) {
            $newOff = $off + $take
            Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
            Clear-ConnectLogSyncPending -LogPath $path
            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                $script:ConnectLogSyncOffset = $newOff
                $script:ConnectLogLinesSinceSync = 0
                if ($newOff -lt $fileLen) { $script:ConnectLogLinesSinceSync = 25 }
            }
            $script:LastConnectLogSyncOk = $true
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                if ($script:ConnectLogWriter) {
                    $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE tail_hash_match off=$off take=$take (skipped re-append)")
                }
            } catch { }
            try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
            return
        }
        $remoteBefore = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
        if ($remoteBefore -lt 0) { $remoteBefore = [int64]0 }
        Write-ConnectLogSyncPending -Offset $off -Take $take -RemoteBefore $remoteBefore -LogPath $path

        '''
        t = t.replace(marker, reconcile + marker, 1)
        # Remove duplicate $sshOpts assignment that follows mk
        # Old code has: $sshOpts = @(...) right after $mk and $cat
        print('connect-ui.ps1: inserted reconcile before mk')

    # Fix append success detection: after cat, also verify remote size growth
    old_append = '''        $appendOk = $false
        if ($scpRes.Ok) {
            $catRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $cat)) -TimeoutMs 12000
            if ($catRes.Ok) { $appendOk = $true }
        }
        $scpOk = $appendOk
        if ($scpOk) {
          if ($appendOk) {
            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                $script:ConnectLogSyncOffset = $off + $take
                $newOff = $script:ConnectLogSyncOffset
                $script:ConnectLogLinesSinceSync = 0
            } else {
                $newOff = $off + $take
            }
            Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false'''

    new_append = '''        $appendOk = $false
        if ($scpRes.Ok) {
            $catRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $cat)) -TimeoutMs 12000
            if ($catRes.Ok) { $appendOk = $true }
        }
        # Even if the timed wait says fail, the remote cat may have succeeded — verify by size.
        if (-not $appendOk) {
            $remoteAfter = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
            if ($remoteAfter -ge 0 -and $remoteAfter -ge ($remoteBefore + [int64]$take)) {
                $appendOk = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE size_verify ok before=$remoteBefore after=$remoteAfter take=$take (timeout false-negative)")
                    }
                } catch { }
            }
        }
        $scpOk = $appendOk
        if ($scpOk) {
          if ($appendOk) {
            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                $script:ConnectLogSyncOffset = $off + $take
                $newOff = $script:ConnectLogSyncOffset
                $script:ConnectLogLinesSinceSync = 0
            } else {
                $newOff = $off + $take
            }
            Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
            Clear-ConnectLogSyncPending -LogPath $path
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false'''

    if 'LOG_SYNC_RECONCILE size_verify' in t:
        print('connect-ui.ps1: size_verify already present')
    else:
        if old_append not in t:
            raise SystemExit('old append block not found')
        t = t.replace(old_append, new_append, 1)
        print('connect-ui.ps1: patched append size_verify')

    # Deduplicate $sshOpts if we now declare it twice
    # After our insert we have $sshOpts then later "$sshOpts = @('-o','BatchMode=yes'..."
    # Remove the second assignment only.
    dup = """        $mk = 'mkdir -p \"$HOME/.claude/logs\" && chmod 700 \"$HOME/.claude\" \"$HOME/.claude/logs\" 2>/dev/null; find \"$HOME/.claude/logs\" -type f -mtime +1 -delete 2>/dev/null; true'
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        # Bug 11: cat must surface append failure (no trailing true).
"""
    fixed = """        $mk = 'mkdir -p \"$HOME/.claude/logs\" && chmod 700 \"$HOME/.claude\" \"$HOME/.claude/logs\" 2>/dev/null; find \"$HOME/.claude/logs\" -type f -mtime +1 -delete 2>/dev/null; true'
        # Bug 11: cat must surface append failure (no trailing true).
"""
    if dup in t:
        t = t.replace(dup, fixed, 1)
        print('connect-ui.ps1: removed duplicate sshOpts')

    p.write_text(t, encoding='utf-8', newline='\n')
    print('OK connect-ui.ps1')


def patch_connect_ui_sh():
    p = ROOT / 'scripts/client/connect-ui.sh'
    t = p.read_text(encoding='utf-8')
    if 'LOG_SYNC_RECONCILE' in t:
        print('connect-ui.sh already patched')
        return

    # After off/take computed and chunk written, before scp - insert reconcile.
    needle = '''    if declare -F sshx >/dev/null 2>&1; then
        sshx "$(_server_logs_cleanup_cmd)" >/dev/null 2>&1 || true
    fi

    if scp -o BatchMode=yes -o ConnectTimeout=12 -q "${CONNECT_LOG_PATH}.chunk" "${ALIAS}:${remote_tmp}" 2>/dev/null; then'''

    insert = '''    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---
    pending_file="${CONNECT_LOG_PATH}.sync-pending"
    remote_before=0
    if [ -f "$pending_file" ]; then
        IFS='|' read -r pend_off pend_take pend_r0 < "$pending_file" || true
        if [ "$pend_off" = "$off" ] && [ "$pend_take" = "$take" ]; then
            r_now=0
            if declare -F sshx >/dev/null 2>&1; then
                r_now="$(sshx "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            else
                r_now="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            fi
            : "${r_now:=0}"
            need=$((pend_r0 + pend_take))
            if [ "$r_now" -ge "$need" ] 2>/dev/null; then
                CONNECT_LOG_SYNC_OFF=$((off + take))
                printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
                rm -f "$pending_file" "${CONNECT_LOG_PATH}.chunk"
                flock -u 8 2>/dev/null || true
                return 0
            fi
        fi
    fi
    local_hash="$(sha256sum "${CONNECT_LOG_PATH}.chunk" 2>/dev/null | awk '{print $1}')"
    if [ -n "$local_hash" ]; then
        if declare -F sshx >/dev/null 2>&1; then
            remote_hash="$(sshx "f=\\"\\$HOME/${remote_day}\\"; [ -f \\"\\$f\\" ] || { echo none; exit 0; }; sz=\\$(stat -c%s \\"\\$f\\" 2>/dev/null || echo 0); [ \\"\\$sz\\" -ge ${take} ] || { echo short; exit 0; }; tail -c ${take} \\"\\$f\\" | sha256sum | awk '{print \\$1}'" 2>/dev/null | tr -dc 'a-f0-9')"
        else
            remote_hash="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$ALIAS" "f=\\"\\$HOME/${remote_day}\\"; [ -f \\"\\$f\\" ] || { echo none; exit 0; }; sz=\\$(stat -c%s \\"\\$f\\" 2>/dev/null || echo 0); [ \\"\\$sz\\" -ge ${take} ] || { echo short; exit 0; }; tail -c ${take} \\"\\$f\\" | sha256sum | awk '{print \\$1}'" 2>/dev/null | tr -dc 'a-f0-9')"
        fi
        if [ -n "$remote_hash" ] && [ "$remote_hash" = "$local_hash" ]; then
            CONNECT_LOG_SYNC_OFF=$((off + take))
            printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
            rm -f "$pending_file" "${CONNECT_LOG_PATH}.chunk"
            flock -u 8 2>/dev/null || true
            return 0
        fi
    fi
    if declare -F sshx >/dev/null 2>&1; then
        remote_before="$(sshx "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    else
        remote_before="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    fi
    : "${remote_before:=0}"
    printf '%s|%s|%s' "$off" "$take" "$remote_before" > "$pending_file" 2>/dev/null || true

    if declare -F sshx >/dev/null 2>&1; then
        sshx "$(_server_logs_cleanup_cmd)" >/dev/null 2>&1 || true
    fi

    if scp -o BatchMode=yes -o ConnectTimeout=12 -q "${CONNECT_LOG_PATH}.chunk" "${ALIAS}:${remote_tmp}" 2>/dev/null; then'''

    if needle not in t:
        raise SystemExit('mac sync needle not found')
    t = t.replace(needle, insert, 1)

    # After cat_ok=1 watermark advance, clear pending. Also size-verify when cat_ok=0.
    old_cat = '''        if [ "$cat_ok" = 1 ]; then
            CONNECT_LOG_SYNC_OFF=$((off + take))
            printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
            CONNECT_LOG_LINES_SINCE_SYNC=0'''
    new_cat = '''        if [ "$cat_ok" != 1 ]; then
            # Timeout/false-negative: confirm append via remote size growth.
            if declare -F sshx >/dev/null 2>&1; then
                remote_after="$(sshx "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            else
                remote_after="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            fi
            : "${remote_after:=0}"
            need=$((remote_before + take))
            if [ "$remote_after" -ge "$need" ] 2>/dev/null; then
                cat_ok=1
            fi
        fi
        if [ "$cat_ok" = 1 ]; then
            CONNECT_LOG_SYNC_OFF=$((off + take))
            printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
            rm -f "$pending_file" 2>/dev/null || true
            CONNECT_LOG_LINES_SINCE_SYNC=0'''
    if old_cat not in t:
        raise SystemExit('mac cat_ok block not found')
    t = t.replace(old_cat, new_cat, 1)

    p.write_text(t, encoding='utf-8', newline='\n')
    print('OK connect-ui.sh')


def patch_task_b_auth():
    p = ROOT / 'scripts/client/cursor-auth-laptop.ps1'
    t = p.read_text(encoding='utf-8')
    if 'AUTH_SYNC_BATCH_PROBE' in t:
        print('auth already batched')
        return

    old = '''    Write-AuthSyncLog "AUTH_SYNC: begin force=$Force db_bytes=$dbBytes wal_bytes=$walBytes alias=$Alias remote_path=$RemotePath" 'INFO'
    $swProbe = [System.Diagnostics.Stopwatch]::StartNew()
    $probe = (SshX "test -f /etc/cursor-auth/golden/auth.json && echo yes" 2>$null) -join ''
    $swProbe.Stop()
    Write-AuthPerfLog -Mark 'auth_ssh_probe' -Ms $swProbe.ElapsedMilliseconds -Extra "golden_exists=$($probe -match 'yes')"
    if ($probe -notmatch 'yes') {
        Write-AuthSyncLog 'skip golden auth.json missing on server' 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_missing db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_golden_missing'
        return $skipped
    }
    $swGoldenMeta = [System.Diagnostics.Stopwatch]::StartNew()
    $goldenExportedAt = ((SshX "cat /etc/cursor-auth/golden/exported-at 2>/dev/null") -join '').Trim()
    $swGoldenMeta.Stop()
    Write-AuthPerfLog -Mark 'auth_ssh_golden_meta' -Ms $swGoldenMeta.ElapsedMilliseconds

    Write-AuthSyncLog 'server cursor-auth-sync --force' 'TRACE'
    $swServerSync = [System.Diagnostics.Stopwatch]::StartNew()
    SshX "cursor-auth-sync --force 2>&1" 2>$null | Out-Null
    $swServerSync.Stop()
    Write-AuthPerfLog -Mark 'auth_ssh_server_sync' -Ms $swServerSync.ElapsedMilliseconds

    Write-AuthSyncLog "local_gs=$localGs db=$dbPath db_exists=$(Test-Path $dbPath)" 'DEBUG'

    # The golden token rotates every 6h (cursor-auth-refresh); a merge that was "complete" at
    # the time still goes stale once the server issues a new token, since OAuth refresh_token
    # rotation invalidates the old accessToken/refreshToken pair. Presence alone can't detect
    # that, so also require the local copy to be stamped with the CURRENT golden export.
    $syncedAt = if (Test-Path $syncedAtPath) { (Get-Content $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    $goldenCurrent = $goldenExportedAt -and ($syncedAt -eq $goldenExportedAt)
    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {'''

    new = '''    Write-AuthSyncLog "AUTH_SYNC: begin force=$Force db_bytes=$dbBytes wal_bytes=$walBytes alias=$Alias remote_path=$RemotePath" 'INFO'
    # AUTH_SYNC_BATCH_PROBE: one SSH for golden existence + exported-at (was 2 round-trips).
    $swProbe = [System.Diagnostics.Stopwatch]::StartNew()
    $probeRaw = (SshX @"
if [ -f /etc/cursor-auth/golden/auth.json ]; then
  echo YES
  cat /etc/cursor-auth/golden/exported-at 2>/dev/null
else
  echo NO
fi
"@ 2>$null) -join "`n"
    $swProbe.Stop()
    $probeLines = @($probeRaw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $probe = if ($probeLines.Count -gt 0 -and $probeLines[0] -eq 'YES') { 'yes' } else { 'no' }
    $goldenExportedAt = if ($probe -eq 'yes' -and $probeLines.Count -gt 1) { $probeLines[1] } else { '' }
    Write-AuthPerfLog -Mark 'auth_ssh_probe' -Ms $swProbe.ElapsedMilliseconds -Extra "golden_exists=$($probe -eq 'yes') batched=1"
    if ($probe -ne 'yes') {
        Write-AuthSyncLog 'skip golden auth.json missing on server' 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=false skipped=true reason=golden_missing db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_golden_missing'
        return $skipped
    }
    Write-AuthPerfLog -Mark 'auth_ssh_golden_meta' -Ms 0 -Extra 'batched_into_probe'

    Write-AuthSyncLog "local_gs=$localGs db=$dbPath db_exists=$(Test-Path $dbPath)" 'DEBUG'

    # The golden token rotates every 6h (cursor-auth-refresh); a merge that was "complete" at
    # the time still goes stale once the server issues a new token, since OAuth refresh_token
    # rotation invalidates the old accessToken/refreshToken pair. Presence alone can't detect
    # that, so also require the local copy to be stamped with the CURRENT golden export.
    # IMPORTANT: check already-complete BEFORE cursor-auth-sync --force (was wasting ~3-5s).
    $syncedAt = if (Test-Path $syncedAtPath) { (Get-Content $syncedAtPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    $goldenCurrent = $goldenExportedAt -and ($syncedAt -eq $goldenExportedAt)
    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {'''

    if old not in t:
        raise SystemExit('auth old block not found')
    t = t.replace(old, new, 1)

    # After the already-complete early-return block, we need to run force sync before Get-RemoteCursorAuthFromGolden
    # Find the return of AlreadyComplete and the next $swGoldenScp
    # Insert force sync between end of already-complete block and golden scp.
    marker = '''    $swGoldenScp = [System.Diagnostics.Stopwatch]::StartNew()
    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias'''
    force_block = '''    Write-AuthSyncLog 'server cursor-auth-sync --force' 'TRACE'
    $swServerSync = [System.Diagnostics.Stopwatch]::StartNew()
    SshX "cursor-auth-sync --force 2>&1" 2>$null | Out-Null
    $swServerSync.Stop()
    Write-AuthPerfLog -Mark 'auth_ssh_server_sync' -Ms $swServerSync.ElapsedMilliseconds

    $swGoldenScp = [System.Diagnostics.Stopwatch]::StartNew()
    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias'''
    if marker not in t:
        raise SystemExit('auth golden scp marker not found')
    if 'auth_ssh_server_sync' in t[t.find('AlreadyComplete'):t.find('Get-RemoteCursorAuthFromGolden')]:
        # might already have force in wrong place - check
        pass
    t = t.replace(marker, force_block, 1)

    p.write_text(t, encoding='utf-8', newline='\n')
    print('OK cursor-auth-laptop.ps1')


def patch_task_b_probe_and_active():
    # Batch touch+probe in Invoke-LaptopReverseSshProbe
    p = ROOT / 'scripts/client/git-mode.ps1'
    t = p.read_text(encoding='utf-8')

    old_probe = '''    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null" 2>$null | Out-Null
    # Windows OpenSSH has no `true` - use cmd exit 0 (connect.ps1 always runs on Windows laptops).
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $out = (SshX "timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 cmd /c exit 0 2>&1") -join "`n"'''

    new_probe = '''    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    # Batch touch+chmod+probe into one SSH (was 2 round-trips ~1.2s).
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $out = (SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null; timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 cmd /c exit 0 2>&1") -join "`n"'''

    if 'Batch touch+chmod+probe' in t:
        print('probe already batched')
    else:
        if old_probe not in t:
            raise SystemExit('probe block not found')
        t = t.replace(old_probe, new_probe, 1)
        print('OK probe batch')

    # Store LastPushConfActive from PUSH_CONF_RESULT
    old_ok = '''    } else {
        $script:LastPushConfKey = $dedupeKey
        $script:LastPushConfAt = Get-Date
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
    }
}'''
    new_ok = '''    } else {
        $script:LastPushConfKey = $dedupeKey
        $script:LastPushConfAt = Get-Date
        if ($pushLine -match 'active=(\\S*)') {
            $script:LastPushConfActive = $Matches[1]
        }
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
    }
}'''
    if 'LastPushConfActive' in t:
        print('LastPushConfActive already set')
    else:
        if old_ok not in t:
            raise SystemExit('push conf ok block not found')
        t = t.replace(old_ok, new_ok, 1)
        print('OK LastPushConfActive')

    p.write_text(t, encoding='utf-8', newline='\n')

    # connect.ps1: skip ACTIVE_MOUNT grep when we just pushed
    cp = ROOT / 'scripts/client/windows/connect.ps1'
    ct = cp.read_text(encoding='utf-8')
    old_grep = '''            Prepare-ServerSessionParallel -ProjectId $go.Id -MountSrc $mountSrc -Alias $Alias
            $activeOnServer = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null") -join '').Trim()
            Write-ConnectLog "ACTIVE_MOUNT server_conf=$activeOnServer pushed_id=$($go.Id)"'''
    new_grep = '''            Prepare-ServerSessionParallel -ProjectId $go.Id -MountSrc $mountSrc -Alias $Alias
            # Skip extra SSH when Push-ServerConnectConf already returned active= (saves ~600-900ms).
            if ($null -ne $script:LastPushConfActive) {
                $activeOnServer = 'ACTIVE_MOUNT=' + $script:LastPushConfActive
            } else {
                $activeOnServer = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null") -join '').Trim()
            }
            Write-ConnectLog "ACTIVE_MOUNT server_conf=$activeOnServer pushed_id=$($go.Id)"'''
    if 'LastPushConfActive' in ct and 'Skip extra SSH when Push-ServerConnectConf' in ct:
        print('connect.ps1 active skip already present')
    else:
        if old_grep not in ct:
            # maybe multiple occurrences
            count = ct.count("((SshX \"grep -E '^ACTIVE_MOUNT='")
            print('ACTIVE_MOUNT grep count', count)
            if old_grep not in ct:
                raise SystemExit('connect.ps1 active grep block not found')
        ct = ct.replace(old_grep, new_grep, 1)
        cp.write_text(ct, encoding='utf-8', newline='\n')
        print('OK connect.ps1 skip ACTIVE_MOUNT grep')

    # Document ControlMaster hang in Invoke-SshXCore comment
    if 'ControlMaster hangs' not in ct:
        old_cm = '''    # No ControlMaster on Windows OpenSSH here: ControlPath/named-pipe mux fails with
    # "getsockname failed: Not a socket" and breaks SshX. Speedups stay in batched remote cmds.'''
        new_cm = '''    # No ControlMaster on Windows OpenSSH here: ControlPath/named-pipe mux fails with
    # "getsockname failed: Not a socket" and/or hangs on `ssh -MNf` (verified 2026-07-20).
    # Speedups stay in batched remote cmds (auth probe, laptop SSH probe, skip redundant greps).'''
        if old_cm in ct:
            ct = ct.replace(old_cm, new_cm, 1)
            cp.write_text(ct, encoding='utf-8', newline='\n')
            print('OK ControlMaster comment')


def main():
    patch_connect_ui_ps1()
    patch_connect_ui_sh()
    patch_task_b_auth()
    patch_task_b_probe_and_active()
    print('ALL PATCHES DONE')

if __name__ == '__main__':
    main()
