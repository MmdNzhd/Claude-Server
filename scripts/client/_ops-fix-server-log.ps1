$ErrorActionPreference = 'Stop'
$day = '20260721'
$lp = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-$day.log"
$wm = $lp + '.sync-offset'
$target = 'claude-server'
$remoteLog = ".claude/logs/connect-$day.log"
$remoteBak = ".claude/logs/connect-$day.log.bak-pre57-$(Get-Date -Format 'HHmmss')"
$size = (Get-Item -LiteralPath $lp).Length
Write-Host "laptop_bytes=$size"
$sshArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=12')
$backupCmd = 'cp "$HOME/' + $remoteLog + '" "$HOME/' + $remoteBak + '" 2>/dev/null; stat -c%s "$HOME/' + $remoteBak + '" 2>/dev/null'
$bakSize = (& ssh @sshArgs $target $backupCmd).Trim()
Write-Host "backup_bytes=$bakSize path=$remoteBak"
$scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=20','-q', $lp, "${target}:$remoteLog")
& scp @scpArgs
$chmodCmd = 'chmod 600 "$HOME/' + $remoteLog + '" 2>/dev/null'
& ssh @sshArgs $target $chmodCmd | Out-Null
Set-Content -LiteralPath $wm -Value ([string]$size) -Encoding ASCII -NoNewline
Remove-Item -LiteralPath ($lp + '.sync-pending') -Force -ErrorAction SilentlyContinue
$statCmd = 'stat -c%s "$HOME/' + $remoteLog + '"'
$rs = (& ssh @sshArgs $target $statCmd).Trim()
$tailCmd = 'tail -1 "$HOME/' + $remoteLog + '"'
$rl = (& ssh @sshArgs $target $tailCmd).Trim()
Write-Host "server_bytes=$rs"
Write-Host "server_last=$rl"
Write-Host "watermark=$size"
