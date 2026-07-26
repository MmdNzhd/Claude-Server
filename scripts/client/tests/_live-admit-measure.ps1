#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$bat = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect.bat'
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$logFile = Join-Path $logDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'connect-boot\.ps1|connect\.ps1' -and $_.ProcessId -ne $PID } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'Claude-Connect\\connect\.bat' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Start-Sleep -Seconds 2

$startOffset = 0L
if (Test-Path -LiteralPath $logFile) { $startOffset = (Get-Item -LiteralPath $logFile).Length }

$launchAt = Get-Date
$proc = Start-Process -FilePath $bat -WorkingDirectory (Split-Path $bat) -PassThru -WindowStyle Hidden
Write-Host ("LAUNCH pid={0} at {1}" -f $proc.Id, $launchAt.ToString('yyyy-MM-dd HH:mm:ss.fff'))

$deadline = (Get-Date).AddSeconds(90)
$menuAt = $null
$sessionId = $null
$bootstrapAt = $null
$sessionStartAt = $null
$raw = ''
try {
    $fs = [IO.File]::Open($logFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object IO.StreamReader($fs)
        $raw = $sr.ReadToEnd()
        $sr.Dispose()
    } finally { $fs.Dispose() }
} catch { $raw = '' }

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
    if (-not (Test-Path -LiteralPath $logFile)) { continue }
    try {
        $fs = [IO.File]::Open($logFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $null = $fs.Seek([int64]$startOffset, [IO.SeekOrigin]::Begin)
            $sr = New-Object IO.StreamReader($fs)
            $chunk = $sr.ReadToEnd()
            $sr.Dispose()
        } finally { $fs.Dispose() }
    } catch { continue }
    foreach ($line in ($chunk -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        if ($line -match '\[([0-9a-f]{12})\]') { $sessionId = $Matches[1] }
        if ($line -match '^\[([0-9-]+ [0-9:\.]+)\].*BOOTSTRAP: connect\.bat start') {
            $bootstrapAt = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
        }
        if ($line -match '^\[([0-9-]+ [0-9:\.]+)\].*session start v') {
            $sessionStartAt = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
        }
        if ($line -match '^\[([0-9-]+ [0-9:\.]+)\].*INTERACTIVE: project_menu_shown') {
            $menuAt = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
            break
        }
    }
    if ($menuAt) { break }
}

if (-not $menuAt) {
    Write-Host 'FAIL no project_menu_shown within 90s'
    exit 2
}

$clickMs = [int]($menuAt - $launchAt).TotalMilliseconds
$bootMs = if ($bootstrapAt) { [int]($menuAt - $bootstrapAt).TotalMilliseconds } else { -1 }
$sessMs = if ($sessionStartAt) { [int]($menuAt - $sessionStartAt).TotalMilliseconds } else { -1 }

Write-Host "SESSION=$sessionId"
Write-Host "MENU_AT=$($menuAt.ToString('yyyy-MM-dd HH:mm:ss.fff'))"
Write-Host "CLICK_TO_MENU_MS=$clickMs"
Write-Host "BOOTSTRAP_TO_MENU_MS=$bootMs"
Write-Host "SESSION_TO_MENU_MS=$sessMs"

$block = ''
if ($sessionId) {
    $m = [regex]::Match($raw, ('(?ms)\[{0}\][\s\S]*?project_menu_shown' -f [regex]::Escape($sessionId)))
    if ($m.Success) { $block = $m.Value }
}
Write-Host ("LOG_HAS_UPDATE={0}" -f ([bool]($block -match 'UPDATE:')))
Write-Host ("LOG_SKIP_PULL={0}" -f ([bool]($block -match 'BOOTSTRAP_PULL: skip canon already current')))
Write-Host ("LOG_PREMENU_TUNNEL={0}" -f ([bool]($block -match 'Initialize-SessionBgTunnel|PROXY_HEALTH')))

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'connect-boot\.ps1|connect\.ps1' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }

if ($clickMs -le 5000) {
    Write-Host 'ADMIT=PASS'
    exit 0
}
Write-Host 'ADMIT=FAIL'
exit 0
