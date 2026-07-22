$ErrorActionPreference = 'Stop'
$path = 'scripts\client\connect-ui.ps1'
$t = Get-Content $path -Raw

if ($t -notmatch 'LOG_SYNC_RECONCILE') {
  $marker = "        `$day = if (`$path -match 'connect-(\d{8})\.log`$') { `$Matches[1] } else { Get-Date -Format 'yyyyMMdd' }`r`n        `$remoteTmp = `".claude/logs/.connect-buf-`$PID.tmp`"`r`n        `$remoteDay = `".claude/logs/connect-`$day.log`"`r`n        `$mk = 'mkdir -p"
  # try LF only
  $marker = @"
        `$day = if (`$path -match 'connect-(\d{8})\.log`$') { `$Matches[1] } else { Get-Date -Format 'yyyyMMdd' }
        `$remoteTmp = ".claude/logs/.connect-buf-`$PID.tmp"
        `$remoteDay = ".claude/logs/connect-`$day.log"
        `$mk = 'mkdir -p "`$HOME/.claude/logs"
"@
  if ($t -notlike "*$($marker.Substring(0,40))*") {
    # find by unique string
  }
  $idx = $t.IndexOf('        $remoteDay = ".claude/logs/connect-$day.log"')
  if ($idx -lt 0) { throw 'remoteDay line not found' }
  $mkIdx = $t.IndexOf("        `$mk = 'mkdir -p", $idx)
  if ($mkIdx -lt 0) { throw 'mk not found' }

  $reconcile = @'
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---
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
                try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
                return
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

'@
  $t = $t.Insert($mkIdx, $reconcile)
  Write-Host 'inserted reconcile'
} else {
  Write-Host 'reconcile already present'
}

# size verify on append
if ($t -notmatch 'LOG_SYNC_RECONCILE size_verify') {
  $old = @'
        $appendOk = $false
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
            $script:ConnectLogSyncFailLogged = $false
'@
  $new = @'
        $appendOk = $false
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
            $script:ConnectLogSyncFailLogged = $false
'@
  if ($t.Contains($old)) {
    $t = $t.Replace($old, $new)
    Write-Host 'patched size_verify'
  } else {
    throw 'append block not found for size_verify'
  }
} else {
  Write-Host 'size_verify already present'
}

# Remove duplicate $sshOpts if present right after $mk
$dup = @'
        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        # Bug 11: cat must surface append failure (no trailing true).
'@
$fixed = @'
        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        # Bug 11: cat must surface append failure (no trailing true).
'@
if ($t.Contains($dup)) {
  $t = $t.Replace($dup, $fixed)
  Write-Host 'removed duplicate sshOpts'
}

# Ensure $remoteBefore is initialized if reconcile path skipped somehow
if ($t -notmatch '\$remoteBefore = \[int64\]0') {
  # also init before use in size_verify when reconcile didn't set it - already set in reconcile block
}

Set-Content -Path $path -Value $t -Encoding utf8NoBOM
# Actually utf8NoBOM may not exist on older PS - use .NET
[IO.File]::WriteAllText((Resolve-Path $path), $t.TrimStart([char]0xFEFF), [Text.UTF8Encoding]::new($false))
Write-Host 'OK connect-ui.ps1 sync body'

# Parse check
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { $_.ToString() }; throw 'parse failed' }
Write-Host 'PARSE OK'
