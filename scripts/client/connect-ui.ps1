# connect-ui.ps1 - terminal UI helpers (dot-sourced by connect.ps1)
# Requires: Warn, Step helpers may exist in parent scope

$script:ConnectLogWriter = $null
$script:ConnectLogPath = ''
$script:LastSessionStatusKey = ''

function Initialize-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$Version = ''
    )
    $script:ConnectLogPath = Join-Path $ScriptDir 'connect.log'
    if (Test-Path -LiteralPath $script:ConnectLogPath) {
        try {
            $fi = Get-Item -LiteralPath $script:ConnectLogPath
            if ($fi.Length -gt 1572864) {
                $bak = "$script:ConnectLogPath.1"
                if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
                Move-Item -LiteralPath $script:ConnectLogPath -Destination $bak -Force
            }
        } catch { }
    }
    try {
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new(
            $script:ConnectLogPath, $true, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        return
    }
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID ========"
    Write-ConnectLog "log file: $script:ConnectLogPath"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
}

function Write-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (-not $script:ConnectLogWriter) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] $Message")
    } catch { }
}

function Write-ConnectTrace {
    param([Parameter(Mandatory)][string]$Message)
    Write-ConnectLog $Message 'TRACE'
}

function Write-ConnectPhaseLog {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    Write-ConnectLog "${Phase}: $Message" $Level
}

function Write-ConnectTimedLog {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Detail = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    $suffix = if ($Detail) { " $Detail" } else { '' }
    Write-ConnectLog "${Label} ms=$Ms$suffix" $Level
}

function Test-ConnectPerfEnabled {
    if ($env:CLAUDE_CONNECT_PERF_LOG -eq '0') { return $false }
    return $true
}

function Write-ConnectPerfLog {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Extra = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'DEBUG'
    )
    if (-not (Test-ConnectPerfEnabled)) { return }
    $suffix = if ($Extra) { " $Extra" } else { '' }
    Write-ConnectLog "PERF[$Mark] ms=$Ms$suffix" $Level
}

function Invoke-ConnectPerfBlock {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][scriptblock]$Block,
        [string]$Extra = ''
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        return & $Block
    } finally {
        $sw.Stop()
        Write-ConnectPerfLog -Mark $Mark -Ms $sw.ElapsedMilliseconds -Extra $Extra
    }
}

function Write-ConnectSessionOpenSummary {
    if (-not (Test-ConnectPerfEnabled)) { return }
    if (-not $script:ConnectPerf) { return }
    $p = $script:ConnectPerf
    $cim = if ($null -ne $script:LaunchCimCallCount) { $script:LaunchCimCallCount } else { 0 }
    $fixes = if ($script:LaunchPerfFixes) { ($script:LaunchPerfFixes -join ',') } else { 'unknown' }
    $ver = if ($script:ConnectVersion) { $script:ConnectVersion } else { 'unknown' }
    Write-ConnectPerfLog -Mark 'session_open_summary' -Ms 0 -Extra (
        "mount_ms=$($p.MountMs) auth_ms=$($p.AuthMs) open_ms=$($p.OpenMs) diag_ms=$($p.DiagMs) " +
        "ssh_total_ms=$($p.SshMsTotal) ssh_count=$($p.SshCount) cim_total=$cim fixes=$fixes version=$ver"
    )
}

function Close-ConnectLog {
    if (-not $script:ConnectLogWriter) { return }
    try {
        Write-ConnectLog '======== session end ========'
        $script:ConnectLogWriter.Dispose()
    } catch { }
    $script:ConnectLogWriter = $null
}

function Get-TerminalWidth {
    try {
        if ($Host.Name -eq 'ConsoleHost') {
            $w = [Console]::WindowWidth
            $b = [Console]::BufferWidth
            if ($w -gt 0 -and $b -gt 0) { return [Math]::Max(40, [Math]::Min($w, $b)) }
        }
    } catch { }
    return 80
}

function Get-LayoutTier {
    param([int]$Width = (Get-TerminalWidth))
    if ($Width -ge 100) { return 'wide' }
    if ($Width -ge 72)  { return 'normal' }
    if ($Width -ge 60)  { return 'narrow' }
    return 'tiny'
}

function Format-TruncPath {
    param(
        [string]$Path,
        [int]$MaxLen = 40
    )
    if (-not $Path) { return '' }
    if ($Path.Length -le $MaxLen) { return $Path }
    $head = [Math]::Max(8, [int]($MaxLen * 0.4))
    $tail = $MaxLen - $head - 3
    if ($tail -lt 4) { return $Path.Substring(0, $MaxLen - 3) + '...' }
    return $Path.Substring(0, $head) + '...' + $Path.Substring($Path.Length - $tail)
}

function Format-TruncLabel {
    param(
        [string]$Text,
        [int]$MaxLen
    )
    if (-not $Text) { return '' }
    if ($MaxLen -le 0) { return $Text }
    if ($Text.Length -le $MaxLen) { return $Text }
    if ($MaxLen -le 3) { return '...' }
    return $Text.Substring(0, $MaxLen - 3) + '...'
}

function Get-ProjectNameColWidth {
    param(
        [array]$Mounts,
        [int]$TerminalWidth,
        [int]$PathMax
    )
    if (-not $Mounts -or $Mounts.Count -eq 0) { return 14 }
    $maxLabel = ($Mounts | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    if (-not $maxLabel) { $maxLabel = 10 }
    # Longest label + " (active)" must fit in the name column
    $want = $maxLabel + 9
    $fixed = 4 + 2 + 2 + 2 + $PathMax
    $avail = $TerminalWidth - $fixed
    if ($avail -lt 10) { return 0 }
    return [Math]::Max(10, [Math]::Min($want, $avail))
}

function Write-ConnectHeader {
    param(
        [string]$Alias,
        [string]$ServerIP,
        [string]$Version
    )
    $W = Get-TerminalWidth
    $tier = Get-LayoutTier -Width $W
    Write-Host ''
    if ($tier -eq 'tiny') {
        Write-Host '    --- Claude Connect ---' -ForegroundColor Cyan
        Write-Host "    $Alias  |  $ServerIP  |  v$Version" -ForegroundColor DarkGray
    } else {
        $inner = [Math]::Min(44, $W - 4)
        $line = ('=' * $inner)
        Write-Host "    +$line+" -ForegroundColor Cyan
        Write-Host ('    |' + ' Claude Connect '.PadRight($inner) + '|') -ForegroundColor Cyan
        Write-Host "    +$line+" -ForegroundColor Cyan
        Write-Host "    $Alias  |  $ServerIP  |  v$Version" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Write-GitModeBanner {
    param([string]$GitMode)
    # Get-GitModeLabel lives in git-mode.ps1 (dot-sourced before this file)
    $label = Get-GitModeLabel -Mode $GitMode
    $W = Get-TerminalWidth
    if ((Get-LayoutTier -Width $W) -eq 'tiny') {
        Write-Host "    Git: $label (g to change)" -ForegroundColor DarkGray
    } else {
        $desc = switch ($GitMode) {
            'server' { 'full git over SSHFS' }
            'hide'   { 'hide .git on laptop' }
            default  { 'no .git rename; laptop-exec git' }
        }
        Write-Host "    Git mode: $label ($desc) - press g to change" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Write-ProjectTable {
    param(
        [array]$Mounts
    )
    $W = Get-TerminalWidth
    $tier = Get-LayoutTier -Width $W
    Write-Host '    Projects' -ForegroundColor White
    Write-Host ''
    if ($Mounts.Count -eq 0) {
        Write-Host '    (no projects configured)' -ForegroundColor DarkGray
        Write-Host ''
        return
    }
    $pathMax = if ($tier -eq 'wide') { 50 } elseif ($tier -eq 'normal') { 36 } elseif ($tier -eq 'narrow') { 24 } else { 0 }
    $nameCol = if ($pathMax -gt 0) { Get-ProjectNameColWidth -Mounts $Mounts -TerminalWidth $W -PathMax $pathMax } else { 0 }
    if ($pathMax -gt 0 -and $nameCol -eq 0) {
        $tier = 'tiny'
        $pathMax = 0
    }
    $i = 1
    foreach ($m in $Mounts) {
        if ($m.Rpath -and -not (Test-LaptopRpathCompatible -Rpath $m.Rpath -Os 'windows')) { continue }
        $activeTag = if ($m.Active) { ' (active)' } else { '' }
        $osTag = ''
        if ($m.Rpath -and -not (Test-LaptopRpathExists -Rpath $m.Rpath)) { $osTag = ' [missing]' }
        $name = $m.Label
        if ($tier -eq 'tiny') {
            $fg = if ($m.Active) { 'White' } else { 'DarkGray' }
            Write-Host ("    {0}  {1}{2}" -f $i, $name, $activeTag) -ForegroundColor $fg
            if ($m.Rpath) {
                Write-Host ("         {0}" -f ((Format-TruncPath -Path $m.Rpath -MaxLen 56) + $osTag)) -ForegroundColor DarkGray
            }
        } elseif ($pathMax -gt 0) {
            $pathShow = (Format-TruncPath -Path $m.Rpath -MaxLen $pathMax) + $osTag
            $nameMax = $nameCol - $activeTag.Length
            $nameShow = Format-TruncLabel -Text $name -MaxLen $nameMax
            $fmt = "    {0,2}  {1,-$nameCol}  {2}"
            if ($m.Active) {
                Write-Host ($fmt -f $i, ($nameShow + $activeTag), $pathShow) -ForegroundColor White
            } else {
                Write-Host ($fmt -f $i, $nameShow, $pathShow) -ForegroundColor DarkGray
            }
        }
        $i++
    }
    Write-Host ''
    Write-Host '    a add   e edit   d delete   c config   g git   q quit' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-SessionBox {
    param(
        [string[]]$ExtraLines = @()
    )
    Write-Host ''
    Write-Host '    ============================================' -ForegroundColor DarkGray
    Write-Host '    Session active -- keep this window open' -ForegroundColor Cyan
    Write-Host '    G = git mode   R = reconnect   O = reopen editor   Q or Enter = disconnect' -ForegroundColor DarkGray
    Write-Host '    Tip: File > Exit Cursor before Q so Agent chat history saves' -ForegroundColor DarkGray
    foreach ($ln in $ExtraLines) {
        Write-Host "    $ln" -ForegroundColor Yellow
    }
    Write-Host '    ============================================' -ForegroundColor DarkGray
    Write-Host ''
}

function Set-ConnectTitle {
    param([string]$Text)
    try {
        $Host.UI.RawUI.WindowTitle = $Text
    } catch { }
}

function Update-SessionStatusLine {
    param(
        [string]$ProjectLabel,
        [string]$GitLabel,
        [bool]$TunnelOk,
        [bool]$EditorOpen,
        [string]$EditorName = 'Cursor',
        [string]$EditorLabel = '',
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorLabel) { $EditorLabel } elseif ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    Write-Host $line -ForegroundColor DarkCyan
    $statusKey = "$ProjectLabel|$GitLabel|$tunnel|$ed"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-ConnectLog "STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]"
    }
    if ($EditorCmd -and $Alias -and $RemotePath) {
        if (-not $EditorOpen) {
            Write-ConnectTrace "STATUS_TICK project=$ProjectLabel tunnel=$tunnel editor=$ed git=$GitLabel"
            if (Get-Command Get-RemoteEditorStateExplain -ErrorAction SilentlyContinue) {
                Write-ConnectLog "HEARTBEAT: $(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
            }
        } else {
            Write-ConnectTrace "STATUS_OK project=$ProjectLabel tunnel=$tunnel editor=$ed"
        }
    }
}

function Show-ConnectToast {
    param([string]$Message)
    if (-not $Message) { return }
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $escaped = [System.Security.SecurityElement]::Escape($Message)
        $xml = '<toast><visual><binding template="ToastText01"><text id="1">' + $escaped + '</text></binding></visual></toast>'
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude.Connect').Show($toast)
    } catch {
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn $Message }
    }
}

function Write-BootstrapHint {
    param([string]$CfgDir)
    $marker = [System.IO.Path]::Combine($CfgDir, 'bootstrap.done')
    if (Test-Path $marker) {
        Write-Host '    Reconnect ~15s' -ForegroundColor DarkGray
    } else {
        Write-Host '    First setup may take ~1 min' -ForegroundColor DarkGray
    }
}

function Mark-BootstrapDone {
    param([string]$CfgDir)
    $marker = [System.IO.Path]::Combine($CfgDir, 'bootstrap.done')
    Set-Content -Path $marker -Value (Get-Date -Format 'o') -Encoding ASCII -ErrorAction SilentlyContinue | Out-Null
}

function Pick-LaptopFolder {
    param([string]$Prompt = 'Select project folder on your laptop')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Prompt
        $dlg.ShowNewFolderButton = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return ($dlg.SelectedPath -replace '\\', '/')
        }
    } catch { }
    return $null
}

