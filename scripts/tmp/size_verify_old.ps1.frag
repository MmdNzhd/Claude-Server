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
