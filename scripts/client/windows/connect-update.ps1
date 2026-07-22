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


function Write-UpdateMsg {
    param([string]$Msg, [string]$Color = 'DarkGray')
    if (-not $script:Quiet) {
        Write-Host "  $Msg" -ForegroundColor $Color
        [Console]::Out.Flush()
    }
}

function Sync-ConnectExeBesideClient {
    # Existing bat users: after auto-update, Claude-Connect.exe sits next to connect.bat.
    # Also mirror to Desktop so they can see/share the single-file installer.
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
        $desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
        $setup = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe'
        Copy-Item -LiteralPath $exe -Destination $desk -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $exe -Destination $setup -Force -ErrorAction SilentlyContinue
        Write-UpdateFileLog ("exe_promoted path=$exe desk=1")
    } catch {
        Write-UpdateFileLog ("exe_promote_fail $($_.Exception.Message)") 'WARN'
    }
}

function Complete-UpdateCheckHandoff {
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
    } catch { }
}

trap {
    $msg = $_.Exception.Message
    $pos = ''
    try { $pos = $_.InvocationInfo.PositionMessage } catch { }
    try { Write-UpdateFileLog ("UNHANDLED $msg at $pos") 'ERROR' } catch { }
    try { Write-UpdateFileLog ("FAIL UPDATE_UNHANDLED: $msg") 'ERROR' } catch { }
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
        defer_hours = 48
    }
}

function Get-UpdateDeferPath { return (Join-Path (Join-Path $env:USERPROFILE '.config\claude-connect') 'update-defer.txt') }

function Test-UpdateDeferActive {
    param([string]$RemoteVer)
    $path = Get-UpdateDeferPath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $ver = $null; $until = $null
        foreach ($line in ($raw -split "`n")) {
            if ($line -match '^version=(.+)$') { $ver = $Matches[1].Trim() }
            if ($line -match '^until=(.+)$') { $until = $Matches[1].Trim() }
        }
        if ($ver -and $RemoteVer -and $ver -ne $RemoteVer) { return $false }
        if (-not $until) { return $false }
        $dt = [datetime]::Parse($until, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ($dt -gt (Get-Date).ToUniversalTime()) {
            Write-UpdateFileLog "UPDATE_DEFER active until=$until ver=$ver"
            return $true
        }
    } catch {}
    return $false
}

function Save-UpdateDefer {
    param([string]$RemoteVer, [int]$Hours = 48)
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
    $until = (Get-Date).ToUniversalTime().AddHours($Hours).ToString('o')
    @"
version=$RemoteVer
until=$until
"@ | Set-Content -LiteralPath (Get-UpdateDeferPath) -Encoding UTF8
    Write-UpdateFileLog "UPDATE_DEFER saved until=$until ver=$RemoteVer"
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
    # Always user@IP from this package. NEVER Host alias "claude-server"
    # (often points at Smart 210.240 -> Sepidz clients pull frozen .22).
    $ip = Get-LocalServerIp
    if ($env:CLAUDE_UPDATE_SSH_TARGET) {
        $t = $env:CLAUDE_UPDATE_SSH_TARGET.Trim()
        return @{ Target = $t; Display = $t }
    }
    if ($ip) {
        $user = Get-RemoteUserFromConf
        if (-not $user) {
            $user = if ($ip -eq '192.168.250.70') { 'sepidz' } elseif ($ip -eq '192.168.210.240') { 'smart' } else { 'smart' }
        }
        $t = "{0}@{1}" -f $user, $ip
        return @{ Target = $t; Display = $t }
    }
    return @{ Target = 'smart@192.168.210.240'; Display = 'smart@192.168.210.240' }
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
        $got = (Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLowerInvariant()
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
        $got = (Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLowerInvariant()
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
    $fh = Get-FileHash -LiteralPath $local -Algorithm SHA256 -ErrorAction SilentlyContinue
    if (-not $fh -or -not $fh.PSObject.Properties['Hash'] -or -not $fh.Hash) {
        Write-UpdateFileLog ("local_exe_hash_fail local=$local") 'WARN'
        return $false
    }
    $got = ([string]$fh.Hash).ToLowerInvariant()
    if ($got -ne $want) {
        Write-UpdateFileLog ("local_exe_drift local=$local") 'WARN'
        return $false
    }
    Write-UpdateFileLog ("local_exe_ok path=$local")
    return $true
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
    $deskExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
    $deskSetup = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe'
    $canonExe = Join-Path $canon 'Claude-Connect.exe'
    Copy-Item -LiteralPath $tmpExe -Destination $deskExe -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $tmpExe -Destination $deskSetup -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $tmpExe -Destination $canonExe -Force -ErrorAction SilentlyContinue

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
if (-not $localVer) { Write-UpdateFileLog 'no local connect-version.txt - skip' 'WARN'; Complete-UpdateCheckHandoff; exit 0 }

function Get-FallbackServiceUser {
    param([string]$Ip)
    if ($Ip -eq '192.168.250.70') { return 'sepidz' }
    if ($Ip -eq '192.168.210.240') { return 'smart' }
    return 'smart'
}

function Resolve-UpdateEndpoint {
    # Try laptop REMOTE_USER first, then sepidz/smart service account.
    $primary = Get-ServerEndpoint
    Write-UpdateFileLog ("SSH_STAGE resolve primary=$($primary.Display)")
    $ver = Invoke-SshCat -Target $primary.Target -RemotePath "$RemoteBundle/connect-version.txt"
    if ($ver) {
        return @{ Target = $primary.Target; Display = $primary.Display; RemoteVer = $ver }
    }
    $ip = Get-LocalServerIp
    if (-not $ip) { return $null }
    $svc = Get-FallbackServiceUser -Ip $ip
    $user = Get-RemoteUserFromConf
    if ($user -and ($user -ne $svc)) {
        $fb = "{0}@{1}" -f $svc, $ip
        Write-UpdateMsg ("Update retry via {0}" -f $fb) 'DarkGray'
        Write-UpdateFileLog ("SSH_STAGE resolve fallback=$fb")
        $ver2 = Invoke-SshCat -Target $fb -RemotePath "$RemoteBundle/connect-version.txt"
        if ($ver2) {
            return @{ Target = $fb; Display = $fb; RemoteVer = $ver2 }
        }
    } elseif (-not $user) {
        # primary already used service account
    } else {
        # primary was service; try nothing else
    }
    return $null
}

$resolved = Resolve-UpdateEndpoint
if (-not $resolved) {
    $ep = Get-ServerEndpoint
    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) 'DarkYellow'
    Write-UpdateFileLog ("unreachable ep=$($ep.Display)") 'WARN'
    Complete-UpdateCheckHandoff
    exit 0
}
$ep = @{ Target = $resolved.Target; Display = $resolved.Display }
$remoteVer = $resolved.RemoteVer
Write-UpdateMsg ("Update source: {0}" -f $ep.Display) 'DarkGray'

$versionNewer = [bool](Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)
$contentDrift = $false
if (-not $versionNewer) {
    # Prefer EXE-only drift check: if server ships Claude-Connect.exe, only that hash matters.
    $remoteSums = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/checksums.txt"
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
if ($forceReq) { $mode = 'force' }

if ($mode -ne 'force') {
    # UPDATE_SILENT / Quiet must never auto-apply optional updates
    if ($script:Quiet) {
        Write-UpdateMsg 'Optional client update available (skipped in silent check)' 'DarkYellow'
        Write-UpdateFileLog "UPDATE_OPTIONAL_SKIP reason=silent local=$localVer remote=$remoteVer"
        Complete-UpdateCheckHandoff
        exit 0
    }
    if (Test-UpdateDeferActive -RemoteVer $remoteVer) {
        Write-UpdateMsg 'Optional update deferred - continuing with current client' 'DarkYellow'
        Write-UpdateFileLog "UPDATE_OPTIONAL_SKIP reason=defer local=$localVer remote=$remoteVer"
        Complete-UpdateCheckHandoff
        exit 0
    }
    $msg = 'A newer Claude Connect is available. Update now?'
    try { if ($policy.message_optional) { $msg = [string]$policy.message_optional } } catch {}
    Write-UpdateMsg ("{0} (v{1} -> v{2})" -f $msg, $localVer, $remoteVer) 'Cyan'
    $answer = 'Y'
    try {
        Write-Host -NoNewline '  Update now? [Y]es / [N]ot now / [D]efer 48h: '
        $answer = [Console]::ReadLine()
    } catch { $answer = 'Y' }
    if (-not $answer) { $answer = 'Y' }
    $a = $answer.Trim().ToUpperInvariant()
    if ($a -eq 'D' -or $a -eq 'DEFER') {
        $hours = 48
        try { if ($policy.defer_hours) { $hours = [int]$policy.defer_hours } } catch {}
        Save-UpdateDefer -RemoteVer $remoteVer -Hours $hours
        Write-UpdateMsg 'Update deferred for 48 hours' 'DarkYellow'
        Complete-UpdateCheckHandoff
        exit 0
    }
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


# --- EXE-only primary update (bat or EXE launch) ---
Write-UpdateFileLog 'exe_only_primary try=1'
if (Invoke-ExeOnlyClientUpdate -Target $ep.Target -RemoteVer $remoteVer) {
    Write-UpdateMsg "Updated to v$remoteVer" 'Green'
    Write-UpdateFileLog 'applied_ok via=exe_only need_relaunch exit=2'
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
    Sync-ConnectExeBesideClient
    Release-ConnectSingleInstanceForUpdateRelaunch
    exit 2
}

Write-UpdateFileLog 'exe_only_fallback_to_bundle' 'WARN'
Write-UpdateMsg '  EXE update unavailable - falling back to full bundle...' 'DarkYellow'

$manifestRaw = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/manifest.txt"
if (-not $manifestRaw) { Write-UpdateFileLog 'manifest_empty_or_unreachable' 'ERROR'; exit 1 }

$files = @($manifestRaw -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($files.Count -eq 0) { Write-UpdateFileLog 'manifest_zero_files' 'ERROR'; exit 1 }

Write-UpdateFileLog ("manifest_files=$($files.Count)")
Write-UpdateMsg '  downloading client bundle...' 'DarkGray'
if (-not (Invoke-BundleDownload -Target $ep.Target -RemoteBundlePath $RemoteBundle -LocalStagingRoot $StagingDir)) {
    Write-UpdateMsg '[!] Update download failed - using local copy' 'DarkYellow'
    Write-UpdateFileLog 'download_failed' 'ERROR'
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Package layout: .../claude-code/{windows,mac}/
# Bundle manifest uses flat windows files + mac/* + server/*.
# Apply is staged to a temp tree then swapped into live dirs (never in-place Copy-Item).

if (-not (Test-BundleChecksums -StagingRoot $StagingDir)) {
    Write-UpdateMsg '[!] Update checksum failed - using local copy' 'DarkYellow'
    Write-UpdateFileLog 'checksum_verify_failed exit=1' 'ERROR'
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
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
# Never put .client-update-bak under Live — Move-Item fails with "subdirectory of the source".
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
                return $true
            } catch {
                Write-UpdateFileLog ("swap_inplace_fail err=$($_.Exception.Message)") 'ERROR'
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
    exit 1
}

Write-UpdateMsg "Updated to v$remoteVer" 'Green'
Write-UpdateFileLog "applied_ok need_relaunch exit=2"

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
    Release-ConnectSingleInstanceForUpdateRelaunch
    exit 2

