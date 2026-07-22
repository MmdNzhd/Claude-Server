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
