# connect-update.ps1 - check server client bundle version; download if newer
# Called from connect.bat before connect.ps1. Exit codes:
#   0 = no update needed / unreachable (continue with local copy)
#   1 = update failed (ERROR) - do not treat as up-to-date
#   2 = files updated - caller should relaunch connect.bat

param(
    [string]$ScriptDir = '',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$script:Quiet = $Quiet.IsPresent -or ($env:CLAUDE_CONNECT_UPDATE_QUIET -eq '1')
$script:UpdateProgressForm = $null
$script:UpdateProgressLabel = $null
$script:UpdateProgressBar = $null

function Ensure-ConnectRunId {
    if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
        $env:CLAUDE_CONNECT_RUN_ID = $env:CLAUDE_CONNECT_RUN_ID.Trim()
        return $env:CLAUDE_CONNECT_RUN_ID
    }
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return $env:CLAUDE_CONNECT_RUN_ID
}

if (-not $ScriptDir) {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
}
$ScriptDir = $ScriptDir.TrimEnd('\', '/')
try { $ScriptDir = [IO.Path]::GetFullPath($ScriptDir) } catch {}

function Save-ConnectLaunchDirStamp {
    # Persist where the user launched Claude-Connect*.exe so post-update can drop
    # Claude-Connect-{ver}.exe beside that folder (e.g. Desktop\claude-publish).
    param([string]$Dir = '')
    try {
        $d = ($Dir + '').Trim()
        if (-not $d -and $env:CLAUDE_CONNECT_LAUNCH_DIR) { $d = $env:CLAUDE_CONNECT_LAUNCH_DIR.Trim() }
        if (-not $d) {
            try {
                Get-CimInstance Win32_Process -Filter "Name LIKE 'Claude-Connect%'" -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = [string]$_.ExecutablePath
                    if (-not $p) { return }
                    $leaf = Split-Path -Leaf $p
                    # Prefer versioned / Setup names over the install-folder Claude-Connect.exe
                    if ($leaf -match '^Claude-Connect-\d{8}\.\d+\.exe$' -or $leaf -eq 'Claude-Connect-Setup.exe') {
                        $d = Split-Path -Parent $p
                    } elseif (-not $d -and $leaf -eq 'Claude-Connect.exe') {
                        $parent = Split-Path -Parent $p
                        $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
                        try {
                            if ([IO.Path]::GetFullPath($parent) -ne [IO.Path]::GetFullPath($canon)) { $d = $parent }
                        } catch {}
                    }
                }
            } catch {}
        }
        if (-not $d) { return }
        try { $d = [IO.Path]::GetFullPath($d) } catch { return }
        if (-not (Test-Path -LiteralPath $d)) { return }
        $env:CLAUDE_CONNECT_LAUNCH_DIR = $d
        $stampDir = Join-Path $env:USERPROFILE '.config\claude-connect'
        New-Item -ItemType Directory -Force -Path $stampDir | Out-Null
        Set-Content -LiteralPath (Join-Path $stampDir 'last-launch-dir.txt') -Value $d -Encoding ASCII -NoNewline
    } catch {}
}
Save-ConnectLaunchDirStamp

$null = Ensure-ConnectRunId

$RemoteBundle = if ($env:CLAUDE_CLIENT_BUNDLE) { $env:CLAUDE_CLIENT_BUNDLE.TrimEnd('/') } else { '/usr/local/share/claude-client' }
$StagingDir = Join-Path $ScriptDir '.client-update-staging'
$script:SshCommonOpts = @(
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=8',
    '-o', 'ConnectionAttempts=1',
    '-o', 'ControlMaster=no',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'IdentityAgent=none',
    '-o', 'StrictHostKeyChecking=accept-new'
)



function Test-PathLooksSepidz {
    param([string]$Path)
    if (-not $Path) { return $false }
    $n = $Path.Replace('/', '\').ToLowerInvariant()
    return ($n -match 'claude-code-sepidz') -or ($n -match 'claude-connect-sepidz')
}

function Assert-SmartNotSepidzContaminated {
    param(
        [string]$LaunchPath,
        [string]$ServerIp
    )
    $sepidzPath = Test-PathLooksSepidz -Path $LaunchPath
    $smartCanon = $false
    try {
        $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
        if ($LaunchPath -and $canon) {
            $a = [IO.Path]::GetFullPath($LaunchPath).TrimEnd('\', '/').ToLowerInvariant()
            $b = [IO.Path]::GetFullPath($canon).TrimEnd('\', '/').ToLowerInvariant()
            if ($a -eq $b -or $a.StartsWith($b + '\')) { $smartCanon = $true }
        }
    } catch {}
    # Smart package (.240 / non-Sepidz) must never live under Sepidz folder names.
    if ($sepidzPath -and $ServerIp -ne '192.168.250.70') {
        $msg = 'REFUSE Smart/Sepidz contamination: Smart package under Sepidz path (claude-code-sepidz / Claude-Connect-Sepidz)'
        Write-UpdateFileLog ("FAIL $msg path=$LaunchPath ip=$ServerIp") 'ERROR'
        Write-UpdateMsg $msg 'Red'
        exit 1
    }
    # Sepidz IP only valid under a Sepidz tree â€” never on Smart Desktop\Claude-Connect.
    if ($ServerIp -eq '192.168.250.70' -and (-not $sepidzPath -or $smartCanon)) {
        $msg = 'REFUSE Smart/Sepidz contamination: ServerIP 192.168.250.70 outside Sepidz tree (or Smart Claude-Connect path)'
        Write-UpdateFileLog ("FAIL $msg path=$LaunchPath ip=$ServerIp smart_canon=$smartCanon sepidz_path=$sepidzPath") 'ERROR'
        Write-UpdateMsg $msg 'Red'
        exit 1
    }
}

function Write-UpdateMsg {
    param([string]$Msg, [string]$Color = 'DarkGray')
    if (-not $script:Quiet) {
        Write-Host "  $Msg" -ForegroundColor $Color
        [Console]::Out.Flush()
    }
}


function Test-UpdateProgressUiWanted {
    if ($env:CLAUDE_CONNECT_UPDATE_UI -eq '0') { return $false }
    if ($env:CLAUDE_CONNECT_UPDATE_UI -eq '1') { return $true }
    # Bat early update uses -Quiet but still wants a visible progress window.
    # Mid-session UPDATE_SILENT leaves UPDATE_UI unset -> no modal.
    return (-not $script:Quiet)
}

function Close-UpdateProgressUi {
    try {
        if ($script:UpdateProgressForm) {
            $f = $script:UpdateProgressForm
            $script:UpdateProgressForm = $null
            $script:UpdateProgressLabel = $null
            $script:UpdateProgressBar = $null
            try { $f.Close() } catch { }
            try { $f.Dispose() } catch { }
        }
    } catch { }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

function Show-UpdateProgressUi {
    param([string]$Status = 'Updating Claude Connect...')
    if (-not (Test-UpdateProgressUiWanted)) { return }
    if ($script:UpdateProgressForm) {
        Set-UpdateProgressUi -Status $Status
        return
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Claude Connect'
        $form.Size = New-Object System.Drawing.Size(460, 168)
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.ControlBox = $false
        $form.TopMost = $true
        $form.ShowInTaskbar = $true
        $title = New-Object System.Windows.Forms.Label
        $title.AutoSize = $false
        $title.Location = New-Object System.Drawing.Point(18, 16)
        $title.Size = New-Object System.Drawing.Size(410, 24)
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        $title.Text = 'Updating Claude Connect'
        $label = New-Object System.Windows.Forms.Label
        $label.AutoSize = $false
        $label.Location = New-Object System.Drawing.Point(18, 48)
        $label.Size = New-Object System.Drawing.Size(410, 36)
        $label.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $label.Text = $Status
        $bar = New-Object System.Windows.Forms.ProgressBar
        $bar.Location = New-Object System.Drawing.Point(18, 96)
        $bar.Size = New-Object System.Drawing.Size(410, 22)
        $bar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $bar.MarqueeAnimationSpeed = 30
        $form.Controls.Add($title)
        $form.Controls.Add($label)
        $form.Controls.Add($bar)
        $form.Show()
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        $script:UpdateProgressForm = $form
        $script:UpdateProgressLabel = $label
        $script:UpdateProgressBar = $bar
        Write-UpdateFileLog 'UPDATE_UI shown'
    } catch {
        Write-UpdateFileLog ("UPDATE_UI show_fail err=$($_.Exception.Message)") 'WARN'
    }
}

function Set-UpdateProgressUi {
    param(
        [string]$Status,
        [int]$Percent = -1
    )
    if (-not $script:UpdateProgressForm) { return }
    try {
        if ($Status) { $script:UpdateProgressLabel.Text = $Status }
        if ($Percent -ge 0 -and $script:UpdateProgressBar) {
            if ($script:UpdateProgressBar.Style -ne [System.Windows.Forms.ProgressBarStyle]::Continuous) {
                $script:UpdateProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            }
            $script:UpdateProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
        }
        $script:UpdateProgressForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
}

function Get-SafeFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $fh = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction SilentlyContinue
        if (-not $fh) { return $null }
        $prop = $fh.PSObject.Properties['Hash']
        if (-not $prop -or -not $prop.Value) { return $null }
        return ([string]$prop.Value).ToLowerInvariant()
    } catch { return $null }
}

function Copy-ExeAtomicSwap {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    # #P6: a plain Copy-Item -Force onto $Destination fails silently whenever that exact
    # file is the one currently executing (e.g. the user double-clicked Desktop\Claude-
    # Connect.exe to launch, so this update step is now trying to overwrite its own running
    # image) - Windows denies direct content overwrite of a mapped/running executable.
    # Renaming the running file out of the way first DOES succeed (the OS loader opens exe
    # images with FILE_SHARE_DELETE, so rename/move of the directory entry is allowed even
    # while it is executing); only then copy the new build into the now-free path. This is
    # the standard self-updating-exe rename-swap trick.
    if (Test-Path -LiteralPath $Destination) {
        try {
            if ((Get-SafeFileSha256 $Source) -eq (Get-SafeFileSha256 $Destination)) {
                return $true # already identical - skip the copy/rename dance entirely
            }
        } catch { }
    }
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        return $true
    } catch {
        # Fall through to rename-swap below.
    }
    $old = "$Destination.old-{0}" -f (Get-Date -Format 'yyyyMMddHHmmss')
    try {
        if (Test-Path -LiteralPath $Destination) {
            Rename-Item -LiteralPath $Destination -NewName (Split-Path -Leaf $old) -Force -ErrorAction Stop
        }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        try { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue } catch { } # best-effort; ok if still locked
        return $true
    } catch {
        Write-UpdateFileLog ("exe_promote_fail dest=$Destination err=$($_.Exception.Message)") 'WARN'
        return $false
    }
}

function Get-ConnectExePromoteDirs {
    # Dirs where the new Claude-Connect-{ver}.exe should appear: install/script dir +
    # wherever the user actually launched the EXE (claude-publish, Desktop, …).
    # Never deletes older versioned EXEs.
    param([string]$WinDir)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $dirs = New-Object 'System.Collections.Generic.List[string]'
    $addDir = {
        param($d, $seenSet, $list)
        if (-not $d) { return }
        try { $d = [IO.Path]::GetFullPath($d) } catch { return }
        if (-not (Test-Path -LiteralPath $d)) { return }
        if ($seenSet.Add($d)) { [void]$list.Add($d) }
    }
    & $addDir $WinDir $seen $dirs
    if ($ScriptDir) { & $addDir $ScriptDir $seen $dirs }
    if ($env:CLAUDE_CONNECT_LAUNCH_DIR) { & $addDir $env:CLAUDE_CONNECT_LAUNCH_DIR $seen $dirs }
    $stamp = Join-Path $env:USERPROFILE '.config\claude-connect\last-launch-dir.txt'
    if (Test-Path -LiteralPath $stamp) {
        try { & $addDir ((Get-Content -LiteralPath $stamp -Raw -ErrorAction Stop).Trim()) $seen $dirs } catch {}
    }
    try {
        Get-CimInstance Win32_Process -Filter "Name LIKE 'Claude-Connect%'" -ErrorAction SilentlyContinue | ForEach-Object {
            $p = [string]$_.ExecutablePath
            if ($p -and (Test-Path -LiteralPath $p)) { & $addDir (Split-Path -Parent $p) $seen $dirs }
        }
    } catch {}
    return $dirs
}

function Sync-ConnectExeBesideClient {
    # After update: refresh Claude-Connect.exe beside the install folder, and place
    # Claude-Connect-{ver}.exe next to every launch/install dir we know (ScriptDir,
    # CLAUDE_CONNECT_LAUNCH_DIR, last-launch-dir, running EXE folders). Never delete olds.
    param([string]$VersionLabel = '')
    try {
        $winDir = $ScriptDir
        $leaf = Split-Path -Leaf $ScriptDir
        if ($leaf -eq 'windows') { $winDir = $ScriptDir }
        elseif (Test-Path (Join-Path $ScriptDir 'windows\Claude-Connect.exe')) {
            $winDir = Join-Path $ScriptDir 'windows'
        } elseif (Test-Path (Join-Path $ScriptDir 'Claude-Connect.exe')) {
            $winDir = $ScriptDir
        }
        $exe = Join-Path $winDir 'Claude-Connect.exe'
        if (-not (Test-Path -LiteralPath $exe)) { return }

        $verLabel = ($VersionLabel + '').Trim()
        if (-not $verLabel) {
            try { $verLabel = (Get-LocalVersion + '').Trim() } catch { $verLabel = '' }
        }

        $promoteDirs = @(Get-ConnectExePromoteDirs -WinDir $winDir)
        $written = New-Object System.Collections.Generic.List[string]
        foreach ($dir in $promoteDirs) {
            $dstExe = Join-Path $dir 'Claude-Connect.exe'
            try {
                if (([IO.Path]::GetFullPath($dstExe)) -ne ([IO.Path]::GetFullPath($exe))) {
                    [void](Copy-ExeAtomicSwap -Source $exe -Destination $dstExe)
                }
            } catch {}
            if ($verLabel -match '^\d{8}\.\d+$') {
                $verExe = Join-Path $dir ("Claude-Connect-{0}.exe" -f $verLabel)
                $okVer = Copy-ExeAtomicSwap -Source $exe -Destination $verExe
                Write-UpdateFileLog ("exe_versioned_promoted ver={0} ok={1} path={2}" -f $verLabel, [int]$okVer, $verExe)
                if ($okVer) { $written.Add($verExe) | Out-Null }
            }
        }
        # Legacy Desktop Setup name (additive; never removes other versioned EXEs).
        $desk = Join-Path $env:USERPROFILE 'Desktop'
        try {
            [void](Copy-ExeAtomicSwap -Source $exe -Destination (Join-Path $desk 'Claude-Connect-Setup.exe'))
        } catch {}
        if ($written.Count -gt 0) {
            $script:LastExeVersionedPaths = @($written)
            Write-UpdateFileLog ("exe_promoted dirs={0} versioned={1}" -f $promoteDirs.Count, $written.Count)
        } else {
            Write-UpdateFileLog ("exe_promoted dirs={0} versioned=0" -f $promoteDirs.Count)
        }
    } catch {
        Write-UpdateFileLog ("exe_promote_fail $($_.Exception.Message)") 'WARN'
    }
}

function Complete-UpdateCheckHandoff {
    Close-UpdateProgressUi
    Sync-ConnectExeBesideClient
    # Boot path: connect.bat runs update then connect.ps1 in the same console.
    if (-not $script:Quiet) { [Console]::Out.Flush() }
}



function Get-UpdateLogPath {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path $dir ("connect-{0}.log" -f $day))
}

function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = Ensure-ConnectRunId
        $line = "[$ts] [$Level] [$sid] UPDATE: $Message`n"
        [System.IO.File]::AppendAllText((Get-UpdateLogPath), $line, [System.Text.UTF8Encoding]::new($false))
        if ($Level -eq 'ERROR' -or $Level -eq 'WARN') {
            $bread = Join-Path $env:USERPROFILE '.config\claude-connect\last-fail.txt'
            try { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bread) | Out-Null } catch { }
            [System.IO.File]::AppendAllText($bread, $line.Replace("`n","`r`n"), [System.Text.UTF8Encoding]::new($false))
        }
    } catch { }
}

trap {
    $msg = $_.Exception.Message
    $pos = ''
    try { $pos = $_.InvocationInfo.PositionMessage } catch { }
    try { Write-UpdateFileLog ("UNHANDLED $msg at $pos") 'ERROR' } catch { }
    try { Write-UpdateFileLog ("FAIL UPDATE_UNHANDLED: $msg") 'ERROR' } catch { }
    try { Close-UpdateProgressUi } catch { }
    if (-not $script:Quiet) {
        Write-Host "  [X] Update error: $msg" -ForegroundColor Red
    }
    exit 1
}


function Release-ConnectSingleInstanceForUpdateRelaunch {
    # Silent mid-session check (-Quiet in connect.ps1 runspace): defer restart; keep mutex.
    if ($script:Quiet -and (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue)) {
        return
    }
    # Same runspace (Invoke-ConnectSilentUpdateCheck uses &): release our mutex handle.
    if (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue) {
        Exit-ConnectSingleInstance
        Write-UpdateFileLog 'relaunch_prep released mutex same_process'
        return
    }
    # Boot path: connect-update runs in a separate powershell.exe before connect.ps1.
    # Stop stale connect.ps1 holders so connect.bat exit=2 relaunch can acquire the mutex.
    try {
        $holders = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '(?i)(\\|/)connect\.ps1(\s|$|")' })
        foreach ($p in $holders) {
            Write-UpdateFileLog ("relaunch_prep stop_connect_ps1 pid=$($p.ProcessId)") 'WARN'
            # Killing just the powershell.exe holder leaves its parent `cmd /K "...connect.bat"`
            # console sitting open forever as a dead, empty window (the /K flag keeps it open
            # after its command exits, and there's nothing left inside it to ever close it).
            # Close that parent too, but only when it's actually a plain cmd.exe wrapping THIS
            # holder - never touch an unrelated/unknown parent.
            $parentId = $p.ParentProcessId
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            if ($parentId) {
                try {
                    $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId" -ErrorAction SilentlyContinue
                    if ($parent -and $parent.Name -eq 'cmd.exe' -and $parent.CommandLine -match '(?i)connect\.bat') {
                        Write-UpdateFileLog ("relaunch_prep stop_stale_cmd_window pid=$parentId") 'WARN'
                        Stop-Process -Id $parentId -Force -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
        }
        if ($holders.Count -gt 0) { Start-Sleep -Milliseconds 200 }
    } catch {
        Write-UpdateFileLog ("relaunch_prep stop_fail err=$($_.Exception.Message)") 'WARN'
    }
}


function Get-ClientUpdatePolicy {
    # Prefer server bundle policy, then local copies. StrictMode-safe (no unset script vars).
    $candidates = @()
    $cfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
    $candidates += (Join-Path $cfgDir 'update-policy.json')
    $candidates += (Join-Path $ScriptDir 'client-update-policy.json')
    $pkg = $ScriptDir
    if ((Split-Path -Leaf $ScriptDir) -eq 'windows') { $pkg = Split-Path -Parent $ScriptDir }
    $candidates += (Join-Path $pkg 'client-update-policy.json')
    # Repo layout when developing from Claude-Code-Server checkout
    $repoPolicy = Join-Path (Split-Path -Parent (Split-Path -Parent $pkg)) 'scripts\server\client-update-policy.json'
    $candidates += $repoPolicy
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            try {
                $obj = Get-Content -LiteralPath $c -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($obj) {
                    Write-UpdateFileLog "UPDATE_POLICY source=$c mode=$($obj.mode)"
                    return $obj
                }
            } catch {}
        }
    }
    return [pscustomobject]@{
        mode = 'optional'
        latest = $null
        force_min_version = $null
        message_optional = 'A newer Claude Connect is available. Update now?'
        message_force = 'A required Claude Connect update will be applied now.'
    }
}

# #P1: connect-version.txt can be intentionally/persistently absent on the server
# (e.g. a frozen/disabled update bundle) or the server can be genuinely unreachable.
# Without a memory of that, every single launch pays the full SSH resolution cost
# (primary + up to 2 fallback identities, 3 retries each) for a check that is known
# to fail - observed up to 62s wasted per launch, always before the UAC prompt.
# Cache a recent miss for a short, self-healing window so a real fix on the server
# is picked up again automatically without needing a client restart.
function Get-UpdateMissCachePath { return (Join-Path (Join-Path $env:USERPROFILE '.config\claude-connect') 'update-check-miss.txt') }

function Test-UpdateCheckRecentlyMissed {
    $path = Get-UpdateMissCachePath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $until = $null
        foreach ($line in ($raw -split "`n")) {
            if ($line -match '^until=(.+)$') { $until = $Matches[1].Trim() }
        }
        if (-not $until) { return $false }
        $dt = [datetime]::Parse($until, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ($dt -gt (Get-Date).ToUniversalTime()) { return $true }
    } catch {}
    return $false
}

function Save-UpdateCheckMiss {
    param([int]$Hours = 6, [string]$Reason = 'unreachable_or_missing')
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
    $until = (Get-Date).ToUniversalTime().AddHours($Hours).ToString('o')
    @"
until=$until
reason=$Reason
"@ | Set-Content -LiteralPath (Get-UpdateMissCachePath) -Encoding UTF8
    Write-UpdateFileLog "UPDATE_CHECK_MISS_CACHED until=$until reason=$Reason hours=$Hours"
}

function Clear-UpdateCheckMiss {
    $path = Get-UpdateMissCachePath
    if (Test-Path -LiteralPath $path) {
        try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Test-UpdateForceRequired {
    param($Policy, [string]$LocalVer)
    if (-not $Policy) { return $false }
    $min = $null
    try { $min = [string]$Policy.force_min_version } catch { $min = $null }
    if (-not $min -or $min -eq '' -or $min -eq 'null') { return $false }
    if (Get-Command Test-RemoteVersionNewer -ErrorAction SilentlyContinue) {
        # force if local is older than force_min_version
        return [bool](Test-RemoteVersionNewer -Remote $min -Local $LocalVer) -or ($LocalVer -ne $min -and -not (Test-RemoteVersionNewer -Remote $LocalVer -Local $min))
    }
    return $false
}


function Get-ConnectVersionParts {
    param([string]$Version)
    if ($Version -match '^(\d{8})\.(\d+)$') {
        return @{ Date = [int]$Matches[1]; Build = [int]$Matches[2] }
    }
    return $null
}

function Test-RemoteVersionNewer {
    param([string]$Remote, [string]$Local)
    if (-not $Remote -or -not $Local) { return $false }
    if ($Remote -eq $Local) { return $false }
    $r = Get-ConnectVersionParts $Remote
    $l = Get-ConnectVersionParts $Local
    if ($r -and $l) {
        if ($r.Date -ne $l.Date) { return $r.Date -gt $l.Date }
        return $r.Build -gt $l.Build
    }
    return ($Remote -gt $Local)
}

function Get-LocalVersion {
    $verFile = Join-Path $ScriptDir 'connect-version.txt'
    if (-not (Test-Path $verFile)) { return '' }
    return (Get-Content $verFile -Raw).Trim()
}

function Get-LocalServerIp {
    foreach ($name in @('connect.ps1')) {
        $p = Join-Path $ScriptDir $name
        if (-not (Test-Path $p)) { continue }
        $raw = Get-Content $p -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        $m = [regex]::Match($raw, '(?m)^\s*\$ServerIP\s*=\s*"([^"]+)"')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return ''
}

function Get-RemoteUserFromConf {
    # Prefer the laptop user's own server account (farzadb, hosseinb, ...).
    # Bundle is world-readable; sepidz@ only works for machines with the sepidz deploy key.
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'))
    try {
        $lu = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($lu -match '\\(.+)$') {
            $u = $Matches[1]
            $candidates.Add("C:\Users\$u\.config\claude-connect\connect.conf")
        }
    } catch {}
    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        foreach ($line in Get-Content -LiteralPath $c -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*REMOTE_USER=(.+)$') {
                $u = $Matches[1].Trim().Trim('"').Trim("'")
                if ($u -and ($u -notmatch '[@/\\]')) { return $u }
            }
        }
    }
    return ''
}

function Get-ServerEndpoint {
    # Always user@IP from this package. NEVER Host alias "claude-server".
    # Prefer laptop connect.conf REMOTE_USER (aria/mehrdad/...). Site service
    # accounts (smart/sepidz) are fallback only when conf has no user.
    $ip = Get-LocalServerIp
    if ($env:CLAUDE_UPDATE_SSH_TARGET) {
        $t = $env:CLAUDE_UPDATE_SSH_TARGET.Trim()
        return @{ Target = $t; Display = $t }
    }
    if ($ip) {
        $user = Get-RemoteUserFromConf
        if (-not $user) {
            if ($ip -eq '192.168.250.70') { $user = 'sepidz' }
            elseif ($ip -eq '192.168.210.240') { $user = 'smart' }
            else { $user = 'smart' }
        }
        $t = "{0}@{1}" -f $user, $ip
        return @{ Target = $t; Display = $t }
    }
    $user = Get-RemoteUserFromConf
    if (-not $user) { $user = 'smart' }
    $t = "{0}@192.168.210.240" -f $user
    return @{ Target = $t; Display = $t }
}
function Invoke-SshTimed {
    param(
        [string[]]$ArgumentList,
        [int]$TimeoutMs = 20000,
        [string]$Exe = 'ssh',
        [switch]$RequireStdout
    )
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outFile = Join-Path $env:TEMP "claude-upd-$id.out"
    $errFile = Join-Path $env:TEMP "claude-upd-$id.err"
    try {
        # Do NOT use & ssh ... 2>$null on Windows -- it can hang forever.
        $p = Start-Process -FilePath $Exe -ArgumentList $ArgumentList `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return @{ Ok = $false; Out = ''; ExitCode = -1 }
        }
        # Windows OpenSSH sometimes leaves ExitCode $null even on success; trust stdout/HasExited.
        Start-Sleep -Milliseconds 50
        $out = ''
        $err = ''
        if (Test-Path $outFile) { $out = ((Get-Content $outFile -Raw -ErrorAction SilentlyContinue) + '').Trim() }
        if (Test-Path $errFile) { $err = ((Get-Content $errFile -Raw -ErrorAction SilentlyContinue) + '').Trim() }
        $ec = $null
        try { $ec = $p.ExitCode } catch {}
        $ok = $p.HasExited
        if ($null -ne $ec) { $ok = $ok -and ($ec -eq 0) }
        if ($RequireStdout) { $ok = $ok -and ($out.Length -gt 0) }
        elseif ($err -match '(?i)permission denied|connection (timed out|refused)|could not resolve') { $ok = $false }
        return @{ Ok = [bool]$ok; Out = $out; ExitCode = $ec; Err = $err }
    } finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    Write-UpdateFileLog ("SSH_STAGE cat begin target=$Target path=$RemotePath")
    $args = $script:SshCommonOpts + @($Target, "cat '$RemotePath'")
    # Up to 3 tries (timeout/retry). Caller may still fall back to another account.
    $r = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout
        if ($r.Ok) {
            if ($attempt -gt 1) {
                Write-UpdateFileLog ("SSH_STAGE cat OK target=$Target bytes=$($r.Out.Length) attempt=$attempt")
            } else {
                Write-UpdateFileLog ("SSH_STAGE cat OK target=$Target bytes=$($r.Out.Length)")
            }
            return $r.Out
        }
        $err = ''
        if ($r.ContainsKey('Err')) { $err = [string]$r.Err }
        if ($err.Length -gt 200) { $err = $err.Substring(0, 200) }
        Write-UpdateFileLog ("SSH_STAGE cat FAIL target=$Target attempt=$attempt/3 exit=$($r.ExitCode) err=$err") 'WARN'
        if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
    }
    return $null
}


function Test-BundleChecksums {
    param([string]$StagingRoot)
    $sumFile = Join-Path $StagingRoot 'checksums.txt'
    if (-not (Test-Path -LiteralPath $sumFile)) {
        Write-UpdateFileLog 'checksums_missing skip_verify' 'WARN'
        return $true
    }
    $bad = @()
    foreach ($line in Get-Content -LiteralPath $sumFile -ErrorAction SilentlyContinue) {
        $t = ($line + '').Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        if ($t -notmatch '^(?i)([a-f0-9]{64})\s+\*?(.+)$') { continue }
        $want = $Matches[1].ToLowerInvariant()
        $rel = ($Matches[2] -replace '\\', '/').Trim().TrimStart('./')
        if ($rel -eq 'checksums.txt') { continue }
        $fp = Join-Path $StagingRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $fp)) {
            $bad += "missing:$rel"
            continue
        }
        $got = Get-SafeFileSha256 -Path $fp
        if (-not $got) { $bad += "hashfail:$rel"; continue }
        if ($got -ne $want) { $bad += "mismatch:$rel" }
    }
    if ($bad.Count -gt 0) {
        Write-UpdateFileLog ("checksum_fail count=$($bad.Count) sample=$($bad[0])") 'ERROR'
        return $false
    }
    Write-UpdateFileLog 'checksum_ok'
    return $true
}

function Test-LocalMatchesRemoteChecksums {
    # Version equality is not enough: a folder can show the same connect-version.txt
    # while git-mode.ps1 / editor-launch.ps1 drifted (partial copy, stale publish unzip).
    # Compare live install against server checksums.txt; any mismatch forces a re-download.
    param(
        [Parameter(Mandatory)][string]$ChecksumText,
        [Parameter(Mandatory)][string]$WindowsDir,
        [string]$MacDir = ''
    )
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($ChecksumText -split '\r?\n')) {
        $trim = ($line + '').Trim()
        if (-not $trim -or $trim.StartsWith('#')) { continue }
        if ($trim -notmatch '^(?i)([a-f0-9]{64})\s+\*?(.+)$') { continue }
        $want = $Matches[1].ToLowerInvariant()
        $rel = ($Matches[2] -replace '\\', '/').Trim().TrimStart('./')
        if ($rel -eq 'checksums.txt' -or $rel -eq 'manifest.txt') { continue }
        if ($rel.StartsWith('mac/')) {
            if (-not $MacDir -or -not (Test-Path -LiteralPath $MacDir)) { continue }
            $fp = Join-Path $MacDir ($rel.Substring(4) -replace '/', [IO.Path]::DirectorySeparatorChar)
        } else {
            $fp = Join-Path $WindowsDir ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        }
        if (-not (Test-Path -LiteralPath $fp)) {
            [void]$bad.Add("missing:$rel")
            continue
        }
        $got = Get-SafeFileSha256 -Path $fp
        if (-not $got) { [void]$bad.Add("hashfail:$rel"); continue }
        if ($got -ne $want) { [void]$bad.Add("mismatch:$rel") }
    }
    if ($bad.Count -gt 0) {
        Write-UpdateFileLog ("local_checksum_drift count=$($bad.Count) sample=$($bad[0])") 'WARN'
        return $false
    }
    Write-UpdateFileLog 'local_checksum_ok'
    return $true
}


function Get-LocalConnectExePath {
    $candidates = @(
        (Join-Path $ScriptDir 'Claude-Connect.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-RemoteExeShaFromChecksums {
    param([string]$ChecksumText)
    foreach ($line in ($ChecksumText -split '\r?\n')) {
        $trim = ($line + '').Trim()
        if (-not $trim -or $trim.StartsWith('#')) { continue }
        if ($trim -notmatch '^(?i)([a-f0-9]{64})\s+\*?(.+)$') { continue }
        $rel = ($Matches[2] -replace '\\', '/').Trim().TrimStart('./')
        if ($rel -eq 'Claude-Connect.exe' -or $rel.EndsWith('/Claude-Connect.exe')) {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return $null
}

function Test-LocalExeMatchesRemoteHash {
    # $true = match, $false = mismatch/missing, $null = no EXE on server checksums
    param([string]$ChecksumText)
    $want = Get-RemoteExeShaFromChecksums -ChecksumText $ChecksumText
    if (-not $want) { return $null }
    $local = Get-LocalConnectExePath
    if (-not $local) {
        Write-UpdateFileLog 'local_exe_missing drift=1'
        return $false
    }
    $got = Get-SafeFileSha256 -Path $local
    if (-not $got) {
        Write-UpdateFileLog ("local_exe_hash_fail local=$local") 'WARN'
        return $false
    }
    if ($got -ne $want) {
        Write-UpdateFileLog ("local_exe_drift local=$local") 'WARN'
        return $false
    }
    Write-UpdateFileLog ("local_exe_ok path=$local")
    return $true
}

function Resolve-ConnectContentDrift {
    param(
        [Parameter(Mandatory)][string]$RemoteVer,
        [Parameter(Mandatory)][string]$LocalVer,
        [Parameter(Mandatory)][string]$Target
    )
    $versionNewer = [bool](Test-RemoteVersionNewer -Remote $RemoteVer -Local $LocalVer)
    $contentDrift = $false
    if (-not $versionNewer) {
        $localExe = Get-LocalConnectExePath
        if (-not $localExe) {
            $contentDrift = $false
            Write-UpdateFileLog 'drift_gate=script_only_ok'
        } else {
            $remoteSums = Invoke-SshCat -Target $Target -RemotePath "$RemoteBundle/checksums.txt"
            if ($remoteSums) {
                $exeMatch = Test-LocalExeMatchesRemoteHash -ChecksumText $remoteSums
                if ($exeMatch -eq $true) {
                    $contentDrift = $false
                    Write-UpdateFileLog 'drift_gate=exe_ok'
                } elseif ($exeMatch -eq $false) {
                    $contentDrift = $true
                    Write-UpdateFileLog 'drift_gate=exe_mismatch'
                } else {
                    # No EXE in remote checksums - legacy full-file compare.
                    $leafGate = Split-Path -Leaf $ScriptDir
                    $winDirGate = $ScriptDir
                    $pkgGate = $ScriptDir
                    if ($leafGate -eq 'windows') {
                        $pkgGate = Split-Path -Parent $ScriptDir
                        $winDirGate = $ScriptDir
                    } elseif (Test-Path (Join-Path $ScriptDir 'windows')) {
                        $winDirGate = Join-Path $ScriptDir 'windows'
                        $pkgGate = $ScriptDir
                    }
                    $macDirGate = Join-Path $pkgGate 'mac'
                    if (-not (Test-Path -LiteralPath $macDirGate)) { $macDirGate = '' }
                    if (-not (Test-LocalMatchesRemoteChecksums -ChecksumText $remoteSums -WindowsDir $winDirGate -MacDir $macDirGate)) {
                        $contentDrift = $true
                    }
                }
            } else {
                Write-UpdateFileLog 'local_checksum_skip remote_checksums_unreachable' 'WARN'
            }
        }
    }
    return @{ VersionNewer = $versionNewer; ContentDrift = $contentDrift }
}

function Test-ConnectExePeValid {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $fs = [IO.File]::OpenRead($Path)
        try {
            $hdr = New-Object byte[] 64
            if ($fs.Read($hdr, 0, 64) -lt 64) { return $false }
            if ($hdr[0] -ne 0x4D -or $hdr[1] -ne 0x5A) { return $false }
            $peOff = [BitConverter]::ToInt32($hdr, 0x3C)
            if ($peOff -lt 64 -or $peOff -gt 1024) { return $false }
            $null = $fs.Seek([int64]$peOff, [IO.SeekOrigin]::Begin)
            $sig = New-Object byte[] 4
            if ($fs.Read($sig, 0, 4) -ne 4) { return $false }
            return ($sig[0] -eq 0x50 -and $sig[1] -eq 0x45 -and $sig[2] -eq 0 -and $sig[3] -eq 0)
        } finally { $fs.Dispose() }
    } catch { return $false }
}

function Test-RemoteExePresent {
    param([string]$Target)
    $cmd = "test -f `"$RemoteBundle/Claude-Connect.exe`" && echo OK || echo NO"
    $r = Invoke-SshTimed -ArgumentList ($script:SshCommonOpts + @($Target, $cmd)) -TimeoutMs 10000
    if (-not $r.Ok) { return $false }
    $out = ''
    if ($r.ContainsKey('Out')) { $out = [string]$r.Out }
    return ($out -match 'OK')
}

function Invoke-ExeOnlyClientUpdate {
    # Download ONLY Claude-Connect.exe, extract into Desktop\Claude-Connect (no second UI),
    # sync files into the live ScriptDir, promote Desktop EXE, then caller exits 2.
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$RemoteVer
    )
    if (-not (Test-RemoteExePresent -Target $Target)) {
        Write-UpdateFileLog 'exe_only_skip remote_exe_missing'
        return $false
    }

    $tmpDir = Join-Path $env:TEMP ("claude-connect-exe-upd-{0}" -f $PID)
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Force -Path $tmpDir
    $tmpExe = Join-Path $tmpDir 'Claude-Connect.exe'

    Set-UpdateProgressUi -Status 'Downloading Claude-Connect.exe...' -Percent 25
    Write-UpdateMsg '  downloading Claude-Connect.exe...' 'DarkGray'
    Write-UpdateFileLog ("exe_only_scp begin target=$Target")
    $scpOpts = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=20',
        '-o', 'ConnectionAttempts=1',
        '-o', 'ControlMaster=no',
        '-o', 'IdentitiesOnly=yes',
        '-o', 'IdentityAgent=none',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-q',
        "${Target}:${RemoteBundle}/Claude-Connect.exe",
        $tmpExe
    )
    $r = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpOpts -TimeoutMs 180000
    if (-not $r.Ok -or -not (Test-Path -LiteralPath $tmpExe)) {
        Write-UpdateFileLog 'exe_only_scp_fail' 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    $len = (Get-Item -LiteralPath $tmpExe).Length
    if ($len -lt 10000) {
        Write-UpdateFileLog ("exe_only_too_small bytes=$len") 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    if (-not (Test-ConnectExePeValid -Path $tmpExe)) {
        Write-UpdateFileLog ("exe_only_pe_invalid bytes=$len") 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-UpdateFileLog ("exe_only_scp_ok bytes=$len pe=1")

    $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
    Set-UpdateProgressUi -Status 'Installing update files...' -Percent 55
    Write-UpdateMsg '  installing from EXE (files only)...' 'DarkGray'
    $prevNoLaunch = $env:CLAUDE_CONNECT_SETUP_NO_LAUNCH
    $env:CLAUDE_CONNECT_SETUP_NO_LAUNCH = '1'
    try {
        $p = Start-Process -FilePath $tmpExe -WorkingDirectory $tmpDir -Wait -PassThru -WindowStyle Hidden
        $ec = 0
        if ($p -and $null -ne $p.ExitCode) { $ec = [int]$p.ExitCode }
        if ($ec -ne 0) {
            Write-UpdateFileLog ("exe_only_setup_fail exit=$ec") 'ERROR'
            return $false
        }
    } finally {
        if ($null -eq $prevNoLaunch -or $prevNoLaunch -eq '') {
            Remove-Item Env:\CLAUDE_CONNECT_SETUP_NO_LAUNCH -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_CONNECT_SETUP_NO_LAUNCH = $prevNoLaunch
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $canon 'connect.bat'))) {
        Write-UpdateFileLog 'exe_only_canon_missing_after_setup' 'ERROR'
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Always place the NEW downloaded EXE on Desktop + inside install folder.
    # When launched FROM the Desktop EXE itself, that file is locked - skip it (folder copy is enough).
    $deskExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
    $deskSetup = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe'
    $canonExe = Join-Path $canon 'Claude-Connect.exe'
    foreach ($pair in @(
        @{ Dst = $deskSetup; Tag = 'desk_setup' },
        @{ Dst = $canonExe; Tag = 'canon_exe' },
        @{ Dst = $deskExe; Tag = 'desk_exe' }
    )) {
        if ($pair.Tag -eq 'desk_exe' -and $env:CLAUDE_CONNECT_FROM_EXE -eq '1') {
            Write-UpdateFileLog 'exe_copy_skip desk_exe reason=from_exe_locked'
            continue
        }
        try {
            Copy-Item -LiteralPath $tmpExe -Destination $pair.Dst -Force -ErrorAction Stop
        } catch {
            Write-UpdateFileLog ("exe_copy_skip tag=$($pair.Tag) err=$($_.Exception.Message -replace '[\r\n]',' ')") 'WARN'
        }
    }

    # If user launched from another folder (old bat), refresh that folder too.
    $liveWin = $ScriptDir
    $leaf = Split-Path -Leaf $ScriptDir
    if ($leaf -eq 'windows') { $liveWin = $ScriptDir }
    elseif (Test-Path (Join-Path $ScriptDir 'connect.bat')) { $liveWin = $ScriptDir }
    try {
        $canonFull = [IO.Path]::GetFullPath($canon)
        $liveFull = [IO.Path]::GetFullPath($liveWin)
    } catch {
        $canonFull = $canon
        $liveFull = $liveWin
    }
    if ($liveFull -and ($liveFull -ne $canonFull) -and (Test-Path -LiteralPath $liveWin)) {
        Write-UpdateFileLog ("exe_only_sync_live live=$liveWin")
        Get-ChildItem -LiteralPath $canon -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^(setup-claude-connect\.cmd|setup-launch\.ps1|READ-ME-USERS\.txt)$') { return }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $liveWin $_.Name) -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $tmpExe -Destination (Join-Path $liveWin 'Claude-Connect.exe') -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-UpdateFileLog ("exe_only_applied ok ver=$RemoteVer")
    return $true
}

function Invoke-BundleDownload {
    param(
        [string]$Target,
        [string]$RemoteBundlePath,
        [string]$LocalStagingRoot
    )
    if (Test-Path $LocalStagingRoot) {
        Remove-Item $LocalStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Force -Path $LocalStagingRoot

    $scpOpts = @(
        '-r',
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=20',
        '-o', 'ConnectionAttempts=1',
        '-o', 'ControlMaster=no',
        '-o', 'IdentitiesOnly=yes',
        '-o', 'IdentityAgent=none',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-q',
        "${Target}:${RemoteBundlePath}/.",
        $LocalStagingRoot
    )
    Write-UpdateFileLog ("SSH_STAGE scp begin target=$Target remote=$RemoteBundlePath")
    $r = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpOpts -TimeoutMs 180000
    if (-not $r.Ok) {
        $err = ''
        if ($r.ContainsKey('Err')) { $err = [string]$r.Err }
        if ($err.Length -gt 400) { $err = $err.Substring(0, 400) }
        Write-UpdateFileLog ("SSH_STAGE scp FAIL target=$Target exit=$($r.ExitCode) err=$err") 'ERROR'
        return $false
    }
    $any = @(Get-ChildItem $LocalStagingRoot -Recurse -File -ErrorAction SilentlyContinue)
    Write-UpdateFileLog ("SSH_STAGE scp OK files=$($any.Count)")
    return ($any.Count -gt 0)
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Write-UpdateFileLog 'ssh_missing' 'ERROR'; exit 1 }
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { Write-UpdateFileLog 'scp_missing' 'ERROR'; exit 1 }

$localVer = Get-LocalVersion
Write-UpdateFileLog ("bat_launch script_dir=$ScriptDir local_ver=$localVer quiet=$($script:Quiet)")
Assert-SmartNotSepidzContaminated -LaunchPath $ScriptDir -ServerIp (Get-LocalServerIp)
if (-not $localVer) { Write-UpdateFileLog 'no local connect-version.txt - skip' 'WARN'; Complete-UpdateCheckHandoff; exit 0 }

function Get-FallbackServiceUser {
    param([string]$Ip)
    if ($Ip -eq '192.168.250.70') { return 'sepidz' }
    if ($Ip -eq '192.168.210.240') { return 'smart' }
    return 'smart'
}

function Resolve-UpdateEndpoint {
    # Primary = REMOTE_USER@IP (or site service if conf empty).
    # Fallback = the other identity (svc <-> developer).
    $primary = Get-ServerEndpoint
    $ip = Get-LocalServerIp
    $svc = if ($ip) { Get-FallbackServiceUser -Ip $ip } else { 'smart' }
    $ru = Get-RemoteUserFromConf
    $ruDisp = if ($ru) { $ru } else { '(none)' }
    Write-UpdateFileLog ("SSH_STAGE resolve primary=$($primary.Display) conf_REMOTE_USER=$ruDisp svc_fallback=$svc")
    $ver = Invoke-SshCat -Target $primary.Target -RemotePath "$RemoteBundle/connect-version.txt"
    if ($ver) {
        Write-UpdateFileLog ("SSH_STAGE resolve_ok target=$($primary.Target) via=primary conf_REMOTE_USER=$ruDisp svc_fallback=$svc")
        return @{ Target = $primary.Target; Display = $primary.Display; RemoteVer = $ver }
    }
    if (-not $ip) {
        Write-UpdateFileLog ("SSH_STAGE resolve_fail reason=no_ip primary=$($primary.Display) conf_REMOTE_USER=$ruDisp") 'WARN'
        return $null
    }
    $user = $ru
    $primaryUser = (($primary.Target -split '@')[0] + '').Trim()
    foreach ($u in @($user, $svc)) {
        if (-not $u) { continue }
        if ($u -eq $primaryUser) { continue }
        $fb = "{0}@{1}" -f $u, $ip
        $via = if ($u -eq $svc) { 'svc_fallback' } else { 'conf_REMOTE_USER' }
        Write-UpdateMsg ("Update retry via {0}" -f $fb) 'DarkGray'
        Write-UpdateFileLog ("SSH_STAGE resolve fallback=$fb via=$via conf_REMOTE_USER=$ruDisp svc_fallback=$svc")
        $ver2 = Invoke-SshCat -Target $fb -RemotePath "$RemoteBundle/connect-version.txt"
        if ($ver2) {
            Write-UpdateFileLog ("SSH_STAGE resolve_ok target=$fb via=$via conf_REMOTE_USER=$ruDisp")
            return @{ Target = $fb; Display = $fb; RemoteVer = $ver2 }
        }
    }
    Write-UpdateFileLog ("SSH_STAGE resolve exhausted primary=$($primary.Display) conf_REMOTE_USER=$ruDisp svc_fallback=$svc") 'WARN'
    return $null
}


if (Test-UpdateCheckRecentlyMissed) {
    Write-UpdateFileLog 'SSH_STAGE skip reason=recently_missed_cache'
    Complete-UpdateCheckHandoff
    exit 0
}
$resolved = Resolve-UpdateEndpoint
if (-not $resolved) {
    $ep = Get-ServerEndpoint
    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) 'DarkYellow'
    Write-UpdateFileLog ("unreachable ep=$($ep.Display)") 'WARN'
    Save-UpdateCheckMiss -Hours 6 -Reason 'resolve_exhausted'
    Complete-UpdateCheckHandoff
    exit 0
}
Clear-UpdateCheckMiss
$ep = @{ Target = $resolved.Target; Display = $resolved.Display }
$remoteVer = $resolved.RemoteVer
Write-UpdateMsg ("Update source: {0}" -f $ep.Display) 'DarkGray'

$driftState = Resolve-ConnectContentDrift -RemoteVer $remoteVer -LocalVer $localVer -Target $ep.Target
$versionNewer = $driftState.VersionNewer
$contentDrift = $driftState.ContentDrift

if (-not $versionNewer -and -not $contentDrift) {
    Write-UpdateMsg "Client up to date (v$localVer)" 'DarkGray'
    Write-UpdateFileLog "up_to_date v$localVer"
    Complete-UpdateCheckHandoff
    exit 0
}

if ($contentDrift) {
    Write-UpdateMsg "Client files out of sync with server (v$localVer) - repairing..." 'Cyan'
    Write-UpdateFileLog "content_mismatch repair local_ver=$localVer remote_ver=$remoteVer"
} else {
    Write-UpdateMsg "Client update available: v$localVer -> v$remoteVer" 'Cyan'
    Write-UpdateFileLog "available v$localVer -> v$remoteVer"
}


# --- Optional / Force policy (Phase D) ---
$policy = Get-ClientUpdatePolicy
# Try remote policy from bundle (non-fatal)
try {
    $remotePolicyRaw = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/client-update-policy.json"
    if ($remotePolicyRaw) {
        $rp = $remotePolicyRaw | ConvertFrom-Json -ErrorAction Stop
        if ($rp) { $policy = $rp; Write-UpdateFileLog 'UPDATE_POLICY source=remote_bundle' }
    }
} catch {}
$forceReq = Test-UpdateForceRequired -Policy $policy -LocalVer $localVer
$mode = 'optional'
try { if ($policy.mode) { $mode = [string]$policy.mode } } catch {}
# UPDATE_FORCE / applied_ok only when policy mode is force AND force_min requires it.
$forceApply = ($mode -eq 'force') -and $forceReq

if (-not $forceApply) {
    # UPDATE_SILENT / Quiet must never auto-apply optional updates
    if ($script:Quiet) {
        Write-UpdateMsg 'Optional client update available (skipped in silent check)' 'DarkYellow'
        Write-UpdateFileLog "UPDATE_OPTIONAL_SKIP reason=silent local=$localVer remote=$remoteVer"
        Complete-UpdateCheckHandoff
        exit 0
    }
    # Defer option removed — drop any leftover stamp from older clients.
    try {
        $deferPath = Join-Path (Join-Path $env:USERPROFILE '.config\claude-connect') 'update-defer.txt'
        if (Test-Path -LiteralPath $deferPath) { Remove-Item -LiteralPath $deferPath -Force -ErrorAction SilentlyContinue }
    } catch {}
    $msg = 'A newer Claude Connect is available. Update now?'
    try { if ($policy.message_optional) { $msg = [string]$policy.message_optional } } catch {}
    Write-UpdateMsg ("{0} (v{1} -> v{2})" -f $msg, $localVer, $remoteVer) 'Cyan'
    $answer = 'N'
    # Automation / hard tests: avoid [Console]::ReadLine when stdin is a pipe that SSH
    # or redirected hosts may already have consumed. Interactive UI unchanged.
    if ($env:CLAUDE_CONNECT_UPDATE_YES -eq '1') {
        $answer = 'Y'
        Write-UpdateFileLog 'UPDATE_OPTIONAL_ANSWER source=CLAUDE_CONNECT_UPDATE_YES'
    } else {
        try {
            Write-Host -NoNewline '  Update now? [Y]es / [N]ot now: '
            $answer = [Console]::ReadLine()
        } catch { $answer = 'N' }
    }
    if (-not $answer) { $answer = 'N' }
    $a = $answer.Trim().ToUpperInvariant()
    if ($a -eq 'N' -or $a -eq 'NO') {
        Write-UpdateFileLog "UPDATE_OPTIONAL_SKIP reason=user_no local=$localVer remote=$remoteVer"
        Complete-UpdateCheckHandoff
        exit 0
    }
} else {
    $fmsg = 'A required Claude Connect update will be applied now.'
    try { if ($policy.message_force) { $fmsg = [string]$policy.message_force } } catch {}
    Write-UpdateMsg $fmsg 'Yellow'
    Write-UpdateFileLog "UPDATE_FORCE applying local=$localVer remote=$remoteVer min=$($policy.force_min_version)"
}


# --- Bundle primary (scripts are source of truth) ---
# Do NOT use Claude-Connect.exe SFX extract as the primary updater: scripts-only
# server deploys keep the previous EXE binary, so extracting it would reinstall
# stale scripts and never land the new connect-version / sidecar fixes.
Show-UpdateProgressUi -Status 'Preparing update...'
Set-UpdateProgressUi -Status ('Updating to v{0}...' -f $remoteVer) -Percent 5
Write-UpdateFileLog 'bundle_primary try=1 reason=scripts_source_of_truth'

$manifestRaw = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/manifest.txt"
if (-not $manifestRaw) { Write-UpdateFileLog 'manifest_empty_or_unreachable' 'ERROR'; Close-UpdateProgressUi; exit 1 }

$files = @($manifestRaw -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($files.Count -eq 0) { Write-UpdateFileLog 'manifest_zero_files' 'ERROR'; Close-UpdateProgressUi; exit 1 }

Write-UpdateFileLog ("manifest_files=$($files.Count)")
Set-UpdateProgressUi -Status 'Downloading client bundle...' -Percent 35
Write-UpdateMsg '  downloading client bundle...' 'DarkGray'
if (-not (Invoke-BundleDownload -Target $ep.Target -RemoteBundlePath $RemoteBundle -LocalStagingRoot $StagingDir)) {
    Write-UpdateMsg '[!] Update download failed - using local copy' 'DarkYellow'
    Write-UpdateFileLog 'download_failed' 'ERROR'
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    Close-UpdateProgressUi
    exit 1
}

# Package layout: .../claude-code/{windows,mac}/
# Bundle manifest uses flat windows files + mac/* + server/*.
# Apply is staged to a temp tree then swapped into live dirs (never in-place Copy-Item).

if (-not (Test-BundleChecksums -StagingRoot $StagingDir)) {
    Write-UpdateMsg '[!] Update checksum failed - using local copy' 'DarkYellow'
    Write-UpdateFileLog 'checksum_verify_failed exit=1' 'ERROR'
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    Close-UpdateProgressUi
    exit 1
}

$leaf = Split-Path -Leaf $ScriptDir
$packageRoot = $ScriptDir
$windowsDir = $ScriptDir
if ($leaf -eq 'windows') {
    $packageRoot = Split-Path -Parent $ScriptDir
    $windowsDir = $ScriptDir
} elseif (Test-Path (Join-Path $ScriptDir 'windows')) {
    $windowsDir = Join-Path $ScriptDir 'windows'
    $packageRoot = $ScriptDir
}
$macDir = Join-Path $packageRoot 'mac'

# Flat Desktop layout (sync-desktop): windowsDir == packageRoot.
# Never put .client-update-bak under Live â€” Move-Item fails with "subdirectory of the source".
$NewRoot = Join-Path $packageRoot '.client-update-new'
$BakRoot = Join-Path $packageRoot '.client-update-bak'
if ($windowsDir -eq $packageRoot) {
    $ext = Join-Path $env:TEMP ("claude-client-update-{0}" -f $PID)
    $NewRoot = Join-Path $ext 'new'
    $BakRoot = Join-Path $ext 'bak'
    Write-UpdateFileLog ("flat_layout staging_ext=$ext (bak outside live root)")
}
Remove-Item $NewRoot, $BakRoot -Recurse -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Directory -Force -Path (Join-Path $NewRoot 'windows')
if (Test-Path -LiteralPath $macDir) {
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $NewRoot 'mac')
}

$failed = @()

function Copy-Tracked {
    param([string]$Src, [string]$Dst, [string]$Label)
    try {
        $parent = Split-Path $Dst -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Force -Path $parent
        }
        Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
        return $true
    } catch {
        $script:failed += $Label
        Write-UpdateFileLog ("copy_fail label=$Label err=$($_.Exception.Message)") 'ERROR'
        return $false
    }
}

# Seed new tree from live so non-manifest files are preserved, then overlay staging.
if (Test-Path -LiteralPath $windowsDir) {
    Get-ChildItem -LiteralPath $windowsDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $dst = Join-Path (Join-Path $NewRoot 'windows') $_.Name
        [void](Copy-Tracked -Src $_.FullName -Dst $dst -Label ("seed:windows/" + $_.Name))
    }
}
if ((Test-Path -LiteralPath $macDir) -and (Test-Path (Join-Path $NewRoot 'mac'))) {
    Get-ChildItem -LiteralPath $macDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $dst = Join-Path (Join-Path $NewRoot 'mac') $_.Name
        [void](Copy-Tracked -Src $_.FullName -Dst $dst -Label ("seed:mac/" + $_.Name))
    }
}

foreach ($rel in $files) {
    $norm = ($rel -replace '\\', '/').Trim().TrimStart('/')
    if ($norm.StartsWith('server/')) { continue }
    $src = Join-Path $StagingDir ($norm -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $src)) {
        $src = Join-Path $StagingDir $rel
    }
    if (-not (Test-Path -LiteralPath $src)) {
        $failed += $rel
        Write-UpdateFileLog ("staging_missing rel=$norm") 'WARN'
        continue
    }
    if ($norm.StartsWith('mac/')) {
        $dst = Join-Path (Join-Path $NewRoot 'mac') $norm.Substring(4).Replace('/', [IO.Path]::DirectorySeparatorChar)
    } else {
        $dst = Join-Path (Join-Path $NewRoot 'windows') ($norm.Replace('/', [IO.Path]::DirectorySeparatorChar))
    }
    [void](Copy-Tracked -Src $src -Dst $dst -Label $rel)
}

$winVerNew = Join-Path (Join-Path $NewRoot 'windows') 'connect-version.txt'
$macVerNew = Join-Path (Join-Path $NewRoot 'mac') 'connect-version.txt'
if ((Test-Path -LiteralPath $winVerNew) -and (Test-Path (Join-Path $NewRoot 'mac'))) {
    [void](Copy-Tracked -Src $winVerNew -Dst $macVerNew -Label 'sync:mac/connect-version.txt')
}

foreach ($leakName in @('mac', 'server')) {
    $leak = Join-Path (Join-Path $NewRoot 'windows') $leakName
    if (Test-Path -LiteralPath $leak) {
        Remove-Item -LiteralPath $leak -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failed.Count -gt 0) {
    Write-UpdateMsg "[!] Update incomplete ($($failed.Count) files) - using local copy" 'DarkYellow'
    Write-UpdateFileLog ("incomplete_files=$($failed.Count) sample=$($failed[0])") 'ERROR'
    Remove-Item $StagingDir, $NewRoot, $BakRoot -Recurse -Force -ErrorAction SilentlyContinue
    Close-UpdateProgressUi
    exit 1
}

function Restore-FromBak {
    param([string]$Live, [string]$Bak)
    try {
        if (Test-Path -LiteralPath $Live) {
            Remove-Item -LiteralPath $Live -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $Bak) {
            Move-Item -LiteralPath $Bak -Destination $Live -Force -ErrorAction Stop
        }
    } catch {
        Write-UpdateFileLog ("rollback_fail live=$Live err=$($_.Exception.Message)") 'ERROR'
    }
}

function Swap-LiveDir {
    param([string]$Live, [string]$NewDir, [string]$Bak)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $Bak -Parent)
    try {
        if (Test-Path -LiteralPath $Live) {
            if (Test-Path -LiteralPath $Bak) {
                Remove-Item -LiteralPath $Bak -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $Live -Destination $Bak -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $NewDir -Destination $Live -Force -ErrorAction Stop
        return $true
    } catch {
        $err = $_.Exception.Message
        Write-UpdateFileLog ("swap_fail live=$Live err=$err") 'ERROR'
        # Self-update while connect.bat runs from Live: folder is "in use". Fall back to
        # in-place file overwrite (no Move-Item on Live), then caller exits 2 to relaunch.
        if ($err -match 'in use|being used by another process') {
            try {
                Restore-FromBak -Live $Live -Bak $Bak
                if (-not (Test-Path -LiteralPath $Live)) {
                    $null = New-Item -ItemType Directory -Force -Path $Live
                }
                Get-ChildItem -LiteralPath $NewDir -Recurse -Force -File -ErrorAction Stop | ForEach-Object {
                    $rel = $_.FullName.Substring($NewDir.Length).TrimStart('\', '/')
                    $dest = Join-Path $Live $rel
                    $parent = Split-Path $dest -Parent
                    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                        $null = New-Item -ItemType Directory -Force -Path $parent
                    }
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                }
                Write-UpdateFileLog 'swap_inplace_ok reason=live_in_use' 'WARN'
                Write-UpdateFileLog 'UPDATE_SWAP_IN_USE: inplace copy ok; bat will relaunch (exit=2)' 'WARN'
                Write-UpdateFileLog 'UPDATE_EXIT pending=2 reason=swap_inplace_live_in_use' 'WARN'
                return $true
            } catch {
                Write-UpdateFileLog ("swap_inplace_fail err=$($_.Exception.Message)") 'ERROR'
                Write-UpdateFileLog ("UPDATE_EXIT pending=1 reason=swap_inplace_fail") 'ERROR'
            }
        }
        Restore-FromBak -Live $Live -Bak $Bak
        return $false
    }
}

$swapOk = $true
$winNew = Join-Path $NewRoot 'windows'
$winBak = Join-Path $BakRoot 'windows'
if (-not (Swap-LiveDir -Live $windowsDir -NewDir $winNew -Bak $winBak)) {
    $swapOk = $false
}

$macNew = Join-Path $NewRoot 'mac'
if ($swapOk -and (Test-Path -LiteralPath $macNew)) {
    if (-not (Test-Path -LiteralPath $macDir)) {
        $null = New-Item -ItemType Directory -Force -Path $macDir
    }
    $macBak = Join-Path $BakRoot 'mac'
    try {
        if (Test-Path -LiteralPath $macDir) {
            if (Test-Path -LiteralPath $macBak) { Remove-Item $macBak -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $macDir -Destination $macBak -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $macNew -Destination $macDir -Force -ErrorAction Stop
    } catch {
        Write-UpdateFileLog ("swap_fail live=$macDir err=$($_.Exception.Message)") 'ERROR'
        Restore-FromBak -Live $macDir -Bak $macBak
        Restore-FromBak -Live $windowsDir -Bak $winBak
        $swapOk = $false
    }
}

Remove-Item $StagingDir, $NewRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($swapOk) {
    Remove-Item $BakRoot -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-UpdateMsg '[!] Update apply failed - rolled back to previous package' 'DarkYellow'
    Write-UpdateFileLog 'apply_rollback' 'ERROR'
    Write-UpdateFileLog 'UPDATE_EXIT exit=1 reason=apply_rollback_swap_fail' 'ERROR'
    Close-UpdateProgressUi
    exit 1
}

Write-UpdateMsg "Updated to v$remoteVer" 'Green'
try { Sync-ConnectExeBesideClient -VersionLabel $remoteVer } catch {}
$paths = @()
try { if ($script:LastExeVersionedPaths) { $paths = @($script:LastExeVersionedPaths) } } catch { $paths = @() }
if ($paths.Count -gt 0) {
    foreach ($p in $paths) {
        Write-UpdateMsg ("  EXE ready: {0}" -f $p) 'DarkGray'
    }
    Write-UpdateMsg '  (older Claude-Connect-*.exe files kept)' 'DarkGray'
} else {
    Write-UpdateMsg ("  Claude-Connect-{0}.exe: not written beside launch folders (see day log)" -f $remoteVer) 'DarkYellow'
}
$depth = 0
try { if ($env:CLAUDE_CONNECT_UPDATE_DEPTH) { $depth = [int]$env:CLAUDE_CONNECT_UPDATE_DEPTH } } catch { $depth = 0 }
$fromExe = if ($env:CLAUDE_CONNECT_FROM_EXE -eq '1') { '1' } else { '0' }
Write-UpdateFileLog "applied_ok need_relaunch exit=2"
Write-UpdateFileLog ("UPDATE_EXIT exit=2 need_relaunch pid=$PID depth=$depth dir=$ScriptDir from_exe=$fromExe")
Write-UpdateFileLog ("bat_relaunch_attempt via=caller depth=$depth dir=$ScriptDir from_exe=$fromExe")

    # best-effort: ship ONLY unsynced bytes (same .sync-offset watermark as connect-ui)
    try {
        $dayLog = Get-UpdateLogPath
        $cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
        $ru=''; $sip=''
        if (Test-Path $cfg) {
            Get-Content $cfg | ForEach-Object {
                if ($_ -match '^REMOTE_USER=(.+)$') { $ru=$Matches[1].Trim() }
            }
        }
        if (Get-Command Get-LocalServerIp -ErrorAction SilentlyContinue) { $sip = Get-LocalServerIp }
        if ($ru -and $sip -and (Test-Path $dayLog)) {
            $t = "{0}@{1}" -f $ru,$sip
            $wmPath = $dayLog + '.sync-offset'
            $off = 0
            if (Test-Path -LiteralPath $wmPath) {
                $raw = ((Get-Content -LiteralPath $wmPath -Raw -ErrorAction SilentlyContinue) + '').Trim()
                [void][int]::TryParse($raw, [ref]$off)
                if ($off -lt 0) { $off = 0 }
            }
            # W3: chunked FileStream read for day-log ship (avoid full-file load).
            $fileLen = [int64]0
            $take = 0
            $chunk = $null
            $fsRead = $null
            try {
                $fsRead = [System.IO.File]::Open(
                    $dayLog,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
                $fileLen = [int64]$fsRead.Length
                if ($off -gt $fileLen) { $off = 0 }
                if ($off -lt $fileLen) {
                    $take = [int][Math]::Min(512KB, $fileLen - $off)
                    $null = $fsRead.Seek([int64]$off, [System.IO.SeekOrigin]::Begin)
                    $chunk = New-Object byte[] $take
                    $got = $fsRead.Read($chunk, 0, $take)
                    if ($got -lt $take) {
                        $take = $got
                        $trimmed = New-Object byte[] $take
                        [Array]::Copy($chunk, 0, $trimmed, 0, $take)
                        $chunk = $trimmed
                    }
                }
            } finally {
                if ($fsRead) { try { $fsRead.Dispose() } catch { } }
            }
            if ($take -gt 0 -and $null -ne $chunk) {
                $tmpLocal = Join-Path $env:TEMP ("claude-upd-chunk-{0}.log" -f $PID)
                [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)
                $day = Get-Date -Format 'yyyyMMdd'
                $remoteTmp = ".claude/logs/.connect-upd-$PID.tmp"
                $remoteDay = ".claude/logs/connect-$day.log"
                $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; true'
                $sshOpts = $script:SshCommonOpts + @($t, $mk)
                $rMk = Invoke-SshTimed -ArgumentList $sshOpts -TimeoutMs 12000
                if ($rMk.Ok) {
                    $scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-q', $tmpLocal, "${t}:$remoteTmp")
                    $rScp = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpArgs -TimeoutMs 20000
                    if ($rScp.Ok) {
                        # Keep $HOME literal for remote bash (never expand in PowerShell).
                        $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '"; ec=$?; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; exit $ec'
                        $rCat = Invoke-SshTimed -ArgumentList ($script:SshCommonOpts + @($t, $cat)) -TimeoutMs 12000
                        if ($rCat.Ok) {
                            $newOff = $off + $take
                            Set-Content -LiteralPath $wmPath -Value "$newOff" -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
                            Write-UpdateFileLog ("shipped_day_log_to_server target=$t bytes=$take offset=$newOff")
                        } else {
                            Write-UpdateFileLog 'SHIP_FAIL cat' 'WARN'
                        }
                    } else {
                        Write-UpdateFileLog 'SHIP_FAIL scp' 'WARN'
                    }
                } else {
                    Write-UpdateFileLog 'SHIP_FAIL mkdir' 'WARN'
                }
                Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
            } else {
                Write-UpdateFileLog 'ship_skip already_synced'
            }
        } else {
            Write-UpdateFileLog 'ship_skip no_conf_or_log'
        }
    } catch {
        Write-UpdateFileLog ("SHIP_FAIL ex=" + $_.Exception.Message) 'WARN'
    }
    Set-UpdateProgressUi -Status 'Update complete - restarting...' -Percent 100
    Close-UpdateProgressUi
    try {
        Release-ConnectSingleInstanceForUpdateRelaunch
        Write-UpdateFileLog ("bat_relaunch_handoff ok released_mutex pid=$PID depth=$depth dir=$ScriptDir")
    } catch {
        Write-UpdateFileLog ("bat_relaunch_handoff fail err=$($_.Exception.Message -replace '[\r\n]',' ') pid=$PID") 'ERROR'
    }

    # Same-process caller (menu `u`): connect-update was `&`'d inside connect-boot/connect.ps1.
    # `exit 2` returns to the CALLER's in-memory Invoke-ConnectManualUpdate / Wait-ConnectExit,
    # which may still be the PRE-update script and will show "Press Enter to close".
    # Detect live UI (command line / env / Wait-ConnectExit), spawn relaunch, then force-kill this PID.
    $calledFromLiveUi = $false
    try {
        if ($env:CLAUDE_CONNECT_MANUAL_UPDATE -eq '1') { $calledFromLiveUi = $true }
        if (-not $calledFromLiveUi -and (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue)) { $calledFromLiveUi = $true }
        if (-not $calledFromLiveUi) {
            $cl = [string](Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue).CommandLine
            if ($cl -match '(?i)connect-boot\.ps1|(?i)[\\/]connect\.ps1(\s|$|")') { $calledFromLiveUi = $true }
        }
    } catch {}
    if ($calledFromLiveUi) {
        try {
            $bat = Join-Path $ScriptDir 'connect.bat'
            if (Test-Path -LiteralPath $bat) {
                $relaunchDepth = $depth + 1
                $relaunchRunId = [guid]::NewGuid().ToString('N').Substring(0, 12)
                $prevDepth = $env:CLAUDE_CONNECT_UPDATE_DEPTH
                $prevRun = $env:CLAUDE_CONNECT_RUN_ID
                $prevRelaunch = $env:CLAUDE_CONNECT_IS_RELAUNCH
                try {
                    $env:CLAUDE_CONNECT_UPDATE_DEPTH = [string]$relaunchDepth
                    $env:CLAUDE_CONNECT_RUN_ID = $relaunchRunId
                    $env:CLAUDE_CONNECT_IS_RELAUNCH = '1'
                    Start-Process -FilePath $bat -WorkingDirectory $ScriptDir | Out-Null
                    Write-UpdateFileLog ("bat_relaunch_from_update_self depth={0} run_id={1}" -f $relaunchDepth, $relaunchRunId)
                } finally {
                    if ($null -eq $prevDepth) { Remove-Item Env:CLAUDE_CONNECT_UPDATE_DEPTH -ErrorAction SilentlyContinue }
                    else { $env:CLAUDE_CONNECT_UPDATE_DEPTH = $prevDepth }
                    if ($null -eq $prevRun) { Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue }
                    else { $env:CLAUDE_CONNECT_RUN_ID = $prevRun }
                    if ($null -eq $prevRelaunch) { Remove-Item Env:CLAUDE_CONNECT_IS_RELAUNCH -ErrorAction SilentlyContinue }
                    else { $env:CLAUDE_CONNECT_IS_RELAUNCH = $prevRelaunch }
                }
            }
        } catch {
            Write-UpdateFileLog ("bat_relaunch_from_update_self_fail err=$($_.Exception.Message)") 'WARN'
        }
        Write-UpdateFileLog ("UPDATE_EXIT exiting=2 kill_self skip_stale_press_enter pid=$PID")
        try {
            $km = Join-Path $env:TEMP 'claude-connect-kill-self.marker'
            Set-Content -LiteralPath $km -Value ("pid={0} t={1}" -f $PID, (Get-Date -Format 'o')) -Encoding ASCII -NoNewline
        } catch {}
        try {
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            # Kill this UI process (and parent connect.bat /K if any) after a brief delay so Start-Process above lands.
            $killCmd = @"
Start-Sleep -Milliseconds 400
try {
  `$self = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue
  if (`$self -and `$self.ParentProcessId) {
    `$par = Get-CimInstance Win32_Process -Filter "ProcessId=`$(`$self.ParentProcessId)" -ErrorAction SilentlyContinue
    if (`$par -and `$par.Name -eq 'cmd.exe' -and (`$par.CommandLine -match '(?i)connect\.bat')) {
      Stop-Process -Id `$par.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
} catch {}
Stop-Process -Id $PID -Force -ErrorAction SilentlyContinue
"@
            Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $killCmd) | Out-Null
        } catch {}
        # Hard exit — do not return to stale Wait-ConnectExit.
        try { [Environment]::Exit(2) } catch { exit 2 }
    }

    # Final breadcrumb after ship so day log always records handoff intent before process dies.
    Write-UpdateFileLog ("UPDATE_EXIT exiting=2 handoff_to_bat_or_exe_setup pid=$PID")
    exit 2

