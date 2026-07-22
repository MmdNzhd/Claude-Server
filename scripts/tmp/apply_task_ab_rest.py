from pathlib import Path
import re

# --- Mac sync ---
p = Path('scripts/client/connect-ui.sh')
t = p.read_text(encoding='utf-8')
if 'LOG_SYNC_RECONCILE' not in t:
    insert = Path('scripts/tmp/mac_sync_insert.sh.frag').read_text(encoding='utf-8')
    needle = '''    if declare -F sshx >/dev/null 2>&1; then
        sshx "$(_server_logs_cleanup_cmd)" >/dev/null 2>&1 || true
    fi

    if scp -o BatchMode=yes -o ConnectTimeout=12 -q "${CONNECT_LOG_PATH}.chunk" "${ALIAS}:${remote_tmp}" 2>/dev/null; then'''
    if needle not in t:
        raise SystemExit('mac needle missing')
    t = t.replace(needle, insert + needle, 1)

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
    # Fix escaping - use simpler remote after without over-escaping
    new_cat = '''        if [ "$cat_ok" != 1 ]; then
            # Timeout/false-negative: confirm append via remote size growth.
            if declare -F sshx >/dev/null 2>&1; then
                remote_after="$(sshx "stat -c%s \\"$HOME/''' + '''${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            else
                remote_after="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \\"$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
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
    # Actually write new_cat cleanly:
    new_cat = (
        '        if [ "$cat_ok" != 1 ]; then\n'
        '            # Timeout/false-negative: confirm append via remote size growth.\n'
        '            if declare -F sshx >/dev/null 2>&1; then\n'
        '                remote_after="$(sshx "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc \'0-9\')"\n'
        '            else\n'
        '                remote_after="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \\"\\$HOME/${remote_day}\\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc \'0-9\')"\n'
        '            fi\n'
        '            : "${remote_after:=0}"\n'
        '            need=$((remote_before + take))\n'
        '            if [ "$remote_after" -ge "$need" ] 2>/dev/null; then\n'
        '                cat_ok=1\n'
        '            fi\n'
        '        fi\n'
        '        if [ "$cat_ok" = 1 ]; then\n'
        '            CONNECT_LOG_SYNC_OFF=$((off + take))\n'
        '            printf \'%s\' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true\n'
        '            rm -f "$pending_file" 2>/dev/null || true\n'
        '            CONNECT_LOG_LINES_SINCE_SYNC=0'
    )
    if old_cat not in t:
        raise SystemExit('mac cat_ok missing')
    t = t.replace(old_cat, new_cat, 1)
    p.write_text(t, encoding='utf-8', newline='\n')
    print('OK mac sync')
else:
    print('mac already patched')

# --- Auth batch ---
ap = Path('scripts/client/cursor-auth-laptop.ps1')
at = ap.read_text(encoding='utf-8')
if 'AUTH_SYNC_BATCH_PROBE' not in at:
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
    $probeRaw = (SshX @'
if [ -f /etc/cursor-auth/golden/auth.json ]; then
  echo YES
  cat /etc/cursor-auth/golden/exported-at 2>/dev/null
else
  echo NO
fi
'@ 2>$null) -join "`n"
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

    if old not in at:
        raise SystemExit('auth old block missing')
    at = at.replace(old, new, 1)

    marker = '''    $swGoldenScp = [System.Diagnostics.Stopwatch]::StartNew()
    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias'''
    force = '''    Write-AuthSyncLog 'server cursor-auth-sync --force' 'TRACE'
    $swServerSync = [System.Diagnostics.Stopwatch]::StartNew()
    SshX "cursor-auth-sync --force 2>&1" 2>$null | Out-Null
    $swServerSync.Stop()
    Write-AuthPerfLog -Mark 'auth_ssh_server_sync' -Ms $swServerSync.ElapsedMilliseconds

    $swGoldenScp = [System.Diagnostics.Stopwatch]::StartNew()
    $authValues = Get-RemoteCursorAuthFromGolden -Alias $Alias'''
    # Only insert force if not already immediately before golden scp after our edit
    idx = at.find(marker)
    if idx < 0:
        raise SystemExit('golden scp marker missing')
    before = at[max(0, idx-200):idx]
    if 'auth_ssh_server_sync' not in before:
        at = at.replace(marker, force, 1)
        print('inserted force sync after already-complete check')
    else:
        print('force already before golden scp')

    ap.write_text(at, encoding='utf-8', newline='\n')
    print('OK auth')
else:
    print('auth already batched')

# --- probe batch + LastPushConfActive ---
gp = Path('scripts/client/git-mode.ps1')
gt = gp.read_text(encoding='utf-8')
old_probe = '''    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null" 2>$null | Out-Null
    # Windows OpenSSH has no `true` - use cmd exit 0 (connect.ps1 always runs on Windows laptops).
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $out = (SshX "timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 cmd /c exit 0 2>&1") -join "`n"'''
new_probe = '''    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    # Batch touch+chmod+probe into one SSH (was 2 round-trips ~1.2s).
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $out = (SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null; timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 cmd /c exit 0 2>&1") -join "`n"'''
if 'Batch touch+chmod+probe' not in gt:
    if old_probe not in gt:
        raise SystemExit('probe block missing')
    gt = gt.replace(old_probe, new_probe, 1)
    print('OK probe')
else:
    print('probe already batched')

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
if 'LastPushConfActive' not in gt:
    if old_ok not in gt:
        raise SystemExit('push ok missing')
    gt = gt.replace(old_ok, new_ok, 1)
    print('OK LastPushConfActive')
else:
    print('LastPushConfActive already')

gp.write_text(gt, encoding='utf-8', newline='\n')

# connect.ps1 ACTIVE_MOUNT skip + ControlMaster comment
cp = Path('scripts/client/windows/connect.ps1')
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
if 'Skip extra SSH when Push-ServerConnectConf' not in ct:
    if old_grep not in ct:
        raise SystemExit('connect active grep missing')
    ct = ct.replace(old_grep, new_grep, 1)
    print('OK active skip')
else:
    print('active skip already')

old_cm = '''    # No ControlMaster on Windows OpenSSH here: ControlPath/named-pipe mux fails with
    # "getsockname failed: Not a socket" and breaks SshX. Speedups stay in batched remote cmds.'''
new_cm = '''    # No ControlMaster on Windows OpenSSH here: ControlPath/named-pipe mux fails with
    # "getsockname failed: Not a socket" and/or hangs on `ssh -MNf` (verified 2026-07-20).
    # Speedups stay in batched remote cmds (auth probe, laptop SSH probe, skip redundant greps).'''
if 'hangs on' not in ct and old_cm in ct:
    ct = ct.replace(old_cm, new_cm, 1)
    print('OK CM comment')

cp.write_text(ct, encoding='utf-8', newline='\n')
print('DONE rest')
