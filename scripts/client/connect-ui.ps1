# connect-ui.ps1 — terminal UI helpers (dot-sourced by connect.ps1)
# Requires: Warn, Step helpers may exist in parent scope

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
        $desc = if ($label -eq 'FAST') { 'hide .git on laptop' } else { 'full git over SSHFS' }
        Write-Host "    Git mode: $label ($desc) - press g to change" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Write-ProjectTable {
    param(
        [array]$Mounts,
        [string]$LastProjectId = ''
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
        $activeTag = if ($m.Active) { ' (active)' } else { '' }
        $name = $m.Label
        if ($tier -eq 'tiny') {
            $fg = if ($m.Active) { 'White' } else { 'DarkGray' }
            Write-Host ("    {0}  {1}{2}" -f $i, $name, $activeTag) -ForegroundColor $fg
            if ($m.Rpath) {
                Write-Host ("         {0}" -f (Format-TruncPath -Path $m.Rpath -MaxLen 56)) -ForegroundColor DarkGray
            }
        } elseif ($pathMax -gt 0) {
            $pathShow = Format-TruncPath -Path $m.Rpath -MaxLen $pathMax
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
    if ($LastProjectId) {
        $lastM = $Mounts | Where-Object { $_.Id -eq $LastProjectId } | Select-Object -First 1
        if ($lastM) {
            Write-Host "    (Enter = $($lastM.Label))" -ForegroundColor DarkGray
        }
    }
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
        [string]$EditorName = 'Cursor'
    )
    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    Write-Host $line -ForegroundColor DarkCyan
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
