# Minimal extract of the real functions
function Get-ConnectLogSyncWatermarkPath {
    param([string]$LogPath)
    return ($LogPath + '.sync-offset')
}
function Read-ConnectLogSyncWatermark {
    param([string]$LogPath)
    $wp = Get-ConnectLogSyncWatermarkPath -LogPath $LogPath
    try {
        if (Test-Path -LiteralPath $wp) {
            $raw = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
            $n = 0
            if ([int]::TryParse($raw, [ref]$n) -and $n -ge 0) { return $n }
        }
    } catch { }
    return 0
}
function Write-ConnectLogSyncWatermark {
    param([int]$Offset, [string]$LogPath)
    Set-Content -LiteralPath (Get-ConnectLogSyncWatermarkPath -LogPath $LogPath) -Value "$Offset" -Encoding ASCII -NoNewline
}

$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$wm = $log + '.sync-offset'
Write-Host ("before disk=[" + [IO.File]::ReadAllText($wm) + "]")
$r1 = Read-ConnectLogSyncWatermark -LogPath $log
Write-Host ("Read returns: " + $r1)
# Simulate reconcile write after "success"
Write-ConnectLogSyncWatermark -Offset (0 + 524288) -LogPath $log
Write-Host ("after Write(524288) disk=[" + [IO.File]::ReadAllText($wm) + "]")
$r2 = Read-ConnectLogSyncWatermark -LogPath $log
Write-Host ("Read AGAIN returns: " + $r2 + "  <-- still 0: watermark appears stuck forever from caller's POV")
# Prove fixed read
$rawFixed = ((Get-Content -LiteralPath $wm -Raw -ErrorAction SilentlyContinue) + '').Trim()
Write-Host ("fixed Read would return: " + $rawFixed)
