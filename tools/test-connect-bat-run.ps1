# connect.bat fast test - 20260722
$ErrorActionPreference = 'Continue'
$WinDir = 'C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$ConnectBat = Join-Path $WinDir 'connect.bat'
$LogDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$Today = Get-Date -Format 'yyyyMMdd'
$LogFile = Join-Path $LogDir "connect-$Today.log"
$DesktopExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
$DesktopFolderExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
$FolderExe = Join-Path $WinDir 'Claude-Connect.exe'
$ServerExe = 'smart@192.168.210.240:/usr/local/share/claude-client/Claude-Connect.exe'
$ExpectedSize = 303104

function Test-PeFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{ ok=$false; reason='MISSING'; size=0 } }
    $fi = Get-Item -LiteralPath $Path
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64) { return @{ ok=$false; reason='TOO_SMALL'; size=$fi.Length } }
    $mz = [char]$bytes[0] + [char]$bytes[1]
    if ($mz -ne 'MZ') { return @{ ok=$false; reason='NO_MZ'; size=$fi.Length } }
    $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOff -ge $bytes.Length - 4) { return @{ ok=$false; reason='BAD_PE_OFFSET'; size=$fi.Length } }
    $sig = [char]$bytes[$peOff] + [char]$bytes[$peOff+1] + [char]$bytes[$peOff+2] + [char]$bytes[$peOff+3]
    if ($sig -ne 'PE' + [char]0 + [char]0) { return @{ ok=$false; reason='NO_PE'; size=$fi.Length } }
    $sizeOk = ($fi.Length -eq $ExpectedSize)
    return @{ ok=$true; reason='OK'; size=$fi.Length; sizeMatch=$sizeOk; pe=$sig.Substring(0,2) }
}

function Pe-Report($label, $path) {
    $r = Test-PeFile $path
    return "$label|$path|ok=$($r.ok)|size=$($r.size)|reason=$($r.reason)|sizeMatch=$($r.sizeMatch)"
}

$report = [ordered]@{}
$report.tunnel = 'UP_assumed'
$report.refetch = 'no'

# Step 2 - before list
$report.before_files = @(Get-ChildItem -LiteralPath $WinDir -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$report.pe_before_folder = Pe-Report 'folder' $FolderExe
$report.pe_before_desktop = Pe-Report 'desktop' $DesktopExe
$report.pe_before_desktop_folder = Pe-Report 'desktop_sub' $DesktopFolderExe

$folderPe = Test-PeFile $FolderExe
if (-not $folderPe.ok) {
    $report.refetch = 'attempting'
    $tmp = Join-Path $env:TEMP 'Claude-Connect-fetch.exe'
    & scp -o StrictHostKeyChecking=no $ServerExe $tmp 2>&1 | Out-String | Set-Variable -Name scpOut
    $fetchPe = Test-PeFile $tmp
    if ($fetchPe.ok) {
        Copy-Item -LiteralPath $tmp -Destination $FolderExe -Force
        $deskDir = Split-Path $DesktopExe
        if (-not (Test-Path $deskDir)) { New-Item -ItemType Directory -Path $deskDir -Force | Out-Null }
        Copy-Item -LiteralPath $tmp -Destination $DesktopExe -Force
        $subDir = Split-Path $DesktopFolderExe
        if (-not (Test-Path $subDir)) { New-Item -ItemType Directory -Path $subDir -Force | Out-Null }
        Copy-Item -LiteralPath $tmp -Destination $DesktopFolderExe -Force
        $report.refetch = 'yes_copied'
    } else {
        $report.refetch = 'yes_scp_failed'
    }
}

# Step 3 - kill stuck only
$killed = @()
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    $cmd = $_.CommandLine
    if ($null -eq $cmd) { return }
    if ($cmd -match 'connect-boot\.ps1' -or ($cmd -match 'Claude-Connect\\connect\.ps1')) {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $killed += $_.ProcessId
    }
}
$report.killed_pids = $killed

# Step 4 - launch bat
$report.bat_exists = Test-Path -LiteralPath $ConnectBat
$launchPid = $null
$proc = $null
if ($report.bat_exists) {
    $proc = Start-Process -FilePath $ConnectBat -WorkingDirectory $WinDir -PassThru
    $launchPid = $proc.Id
    $report.bat_launched = $true
    $report.launch_pid = $launchPid
    Start-Sleep -Seconds 45
    if (-not $proc.HasExited) {
        $report.launch_still_running = $true
        $report.launch_exit = $null
    } else {
        $report.launch_still_running = $false
        $report.launch_exit = $proc.ExitCode
    }
} else {
    $report.bat_launched = $false
}

# Step 5 - log tail
$patterns = 'BOOTSTRAP|UPDATE|FAIL|legacy|redirect|exe_only|up_to_date|healed|cleaned'
$report.log_path = $LogFile
$report.log_exists = Test-Path -LiteralPath $LogFile
$report.log_lines = @()
if ($report.log_exists) {
    $all = Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue
    $matched = $all | Select-String -Pattern $patterns
    $report.log_lines = @($matched | Select-Object -Last 40 | ForEach-Object { $_.Line })
}

# Step 6 - after
$report.after_files = @(Get-ChildItem -LiteralPath $WinDir -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$onlyExe = ($report.after_files.Count -eq 1 -and $report.after_files[0] -eq 'Claude-Connect.exe')
$report.exe_only_folder = $onlyExe
$report.pe_after_folder = Pe-Report 'folder' $FolderExe
$report.pe_after_desktop = Pe-Report 'desktop' $DesktopExe
$report.pe_after_desktop_folder = Pe-Report 'desktop_sub' $DesktopFolderExe

Write-Output '===REPORT_START==='
$report.GetEnumerator() | ForEach-Object {
    $k = $_.Key
    $v = $_.Value
    if ($v -is [array]) {
        Write-Output "$k`:"
        $v | ForEach-Object { Write-Output "  $_" }
    } else {
        Write-Output "$k`: $v"
    }
}
Write-Output '===REPORT_END==='
