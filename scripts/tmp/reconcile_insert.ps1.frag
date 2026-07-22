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

