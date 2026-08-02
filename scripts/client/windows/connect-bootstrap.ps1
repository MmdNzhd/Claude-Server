#Requires -Version 5.1
# connect-bootstrap.ps1 - pull latest client from server into Desktop\Claude-Connect.
# Works even when local connect-update.ps1 is broken (UpdateEndpointTarget / StrictMode).
# Any old folder can recover if OpenSSH + LAN/VPN to server works.
#
# Exit 0 = Canon OK (refreshed or already current); continue
# Exit 2 = relaunch Desktop\Claude-Connect\connect.bat (legacy/broken Here)
# Exit 1 = pull failed (caller may still try local heal)

param(
    [string]$Here = '',
    [switch]$Quiet,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$_connectEnvRepair = Join-Path $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }) 'connect-env-repair.ps1'
if (Test-Path -LiteralPath $_connectEnvRepair) {
    . $_connectEnvRepair
} else {
    # Inline fallback when ancient folders lack connect-env-repair.ps1 (Parsa 8.3).
    try {
        $longProfile = $null
        try {
            $fp = [Environment]::GetFolderPath('UserProfile')
            if ($fp -and ($fp -notmatch '~') -and (Test-Path -LiteralPath $fp)) { $longProfile = $fp }
        } catch {}
        if (-not $longProfile) {
            $u = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
            if ($u -and ($u -notmatch '~')) {
                $guess = Join-Path 'C:\Users' $u
                if (Test-Path -LiteralPath $guess) { $longProfile = $guess }
            }
        }
        if ($longProfile -and ($longProfile -notmatch '~') -and (Test-Path -LiteralPath $longProfile)) {
            if (-not $env:USERPROFILE -or ($env:USERPROFILE -match '~') -or -not (Test-Path -LiteralPath $env:USERPROFILE)) {
                $env:USERPROFILE = $longProfile
            }
            $longLocal = Join-Path $longProfile 'AppData\Local'
            if ((Test-Path -LiteralPath $longLocal) -and (
                    -not $env:LOCALAPPDATA -or ($env:LOCALAPPDATA -match '~') -or -not (Test-Path -LiteralPath $env:LOCALAPPDATA))) {
                $env:LOCALAPPDATA = $longLocal
            }
        }
    } catch {}
    try {
        $tempCandidates = New-Object System.Collections.Generic.List[string]
        if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
            [void]$tempCandidates.Add((Join-Path $env:LOCALAPPDATA 'Temp'))
        }
        if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
            [void]$tempCandidates.Add((Join-Path $env:USERPROFILE 'AppData\Local\Temp'))
        }
        try {
            $p = [IO.Path]::GetTempPath()
            if ($p -and ($p -notmatch '~')) { [void]$tempCandidates.Add($p) }
        } catch {}
        if ($env:TEMP -and ($env:TEMP -notmatch '~')) { [void]$tempCandidates.Add($env:TEMP) }
        if ($env:TMP -and ($env:TMP -notmatch '~')) { [void]$tempCandidates.Add($env:TMP) }
        if ($env:SystemRoot) { [void]$tempCandidates.Add((Join-Path $env:SystemRoot 'Temp')) }
        foreach ($cand in $tempCandidates) {
            if (-not $cand -or ($cand -match '~')) { continue }
            try {
                if (-not (Test-Path -LiteralPath $cand)) {
                    New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
                }
                $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName
                if ($full -and ($full -notmatch '~')) { $env:TEMP = $full; $env:TMP = $full; break }
            } catch { continue }
        }
    } catch {}
}
$_connectEnvRepair = $null

$Canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$RemoteBundle = if ($env:CLAUDE_CLIENT_BUNDLE) { $env:CLAUDE_CLIENT_BUNDLE.TrimEnd('/') } else { '/usr/local/share/claude-client' }
$RelaunchMarker = Join-Path $env:TEMP 'claude-connect-relaunch.dir'
$PreflightHandoff = Join-Path $env:TEMP 'claude-connect-preflight.ok'
$RemoteVerCacheFile = Join-Path $env:TEMP 'claude-connect-remote-ver.cache'
$RemoteVerCacheTtlMinutes = 15
if ($Here) { $Here = $Here.TrimEnd('\', '/') }

function Clear-RemoteVerDiskCache {
    Remove-Item -LiteralPath $RemoteVerCacheFile -Force -ErrorAction SilentlyContinue
}

function Read-RemoteVerDiskCache {
    param([Parameter(Mandatory)][string]$LocalVer)
    if (-not (Test-Path -LiteralPath $RemoteVerCacheFile)) { return $null }
    try {
        $map = @{}
        foreach ($ln in @(Get-Content -LiteralPath $RemoteVerCacheFile -ErrorAction Stop)) {
            if ($ln -match '^([^=]+)=(.*)$') { $map[$Matches[1]] = $Matches[2] }
        }
        if (-not $map['VER'] -or -not $map['TS']) { return $null }
        if ($map['VER'] -ne $LocalVer) { return $null }
        $ts = [datetime]::ParseExact($map['TS'], 'yyyy-MM-dd HH:mm:ss.fff', $null)
        if (((Get-Date) - $ts).TotalMinutes -ge $RemoteVerCacheTtlMinutes) { return $null }
        return [string]$map['VER']
    } catch { return $null }
}

function Write-RemoteVerDiskCache {
    param([Parameter(Mandatory)][string]$Ver)
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        [IO.File]::WriteAllLines($RemoteVerCacheFile, @("VER=$Ver", "TS=$ts"), [Text.UTF8Encoding]::new($false))
    } catch {}
}

function Clear-PreflightHandoff {
    Remove-Item -LiteralPath $PreflightHandoff -Force -ErrorAction SilentlyContinue
}

function Write-PreflightHandoff {
    param([hashtable]$Fields)
    try {
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($k in ($Fields.Keys | Sort-Object)) {
            [void]$lines.Add(('{0}={1}' -f $k, [string]$Fields[$k]))
        }
        [IO.File]::WriteAllLines($PreflightHandoff, $lines.ToArray(), [Text.UTF8Encoding]::new($false))
    } catch {}
}

$PullNames = @(
    'connect.bat',
    'connect-hide-relaunch.vbs',
    'connect-hide-console.ps1',
    'connect-boot.ps1',
    'connect-bootstrap.ps1',
    'connect-heal.ps1',
    'connect-preflight.ps1',
    'connect-env-repair.ps1',
    'connect.ps1',
    'connect-update.ps1',
    'cursor-proxy-sidecar.ps1',
    'connect-ui.ps1',
    'connect-diagnostic.ps1',
    'editor-launch.ps1',
    'git-mode.ps1',
    'cursor-auth-laptop.ps1',
    'windows-mcp-laptop.ps1',
    'connect-version.txt',
    'connect-rider.bat',
    'Claude-Connect.exe'
)

$SshOpts = @(
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=8',
    '-o', 'ConnectionAttempts=1',
    '-o', 'ControlMaster=no',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'IdentityAgent=none',
    '-o', 'StrictHostKeyChecking=accept-new'
)

function Write-BootLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $f = Join-Path $dir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = $env:CLAUDE_CONNECT_RUN_ID
        if (-not $sid) { $sid = '-' }
        $line = '[{0}] [{1}] [{2}] BOOTSTRAP_PULL: {3}' -f $ts, $Level, $sid, $Message
        [IO.File]::AppendAllText($f, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } catch {}
    if (-not $Quiet) {
        try { Write-Host ("  {0}" -f $Message) -ForegroundColor DarkGray } catch {}
    }
}

function Resolve-VersionedSrcUnderRoot {
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    if ((Split-Path -Leaf $Root) -ne 'Claude-Connect') { return $null }
    $ver = ''
    if (Get-Command Get-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
        $ver = Get-ConnectInstallCurrent -Root $Root
    }
    if ($ver -notmatch '^\d{8}\.\d+$') {
        try {
            $cf = Join-Path $Root 'current.txt'
            if (Test-Path -LiteralPath $cf) {
                $ver = (Get-Content -LiteralPath $cf -Raw -ErrorAction SilentlyContinue).Trim()
            }
        } catch { $ver = '' }
    }
    if ($ver -notmatch '^\d{8}\.\d+$') {
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
            Sort-Object Name -Descending |
            Select-Object -First 1 |
            ForEach-Object { $ver = $_.Name }
    }
    if ($ver -notmatch '^\d{8}\.\d+$') { return $null }
    return (Join-Path $Root (Join-Path $ver 'src'))
}

function Test-GoodClientDir {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir) -or -not (Test-Path -LiteralPath $Dir)) { return $false }
    if ((Split-Path -Leaf $Dir) -eq 'Claude-Connect') {
        $vs = Resolve-VersionedSrcUnderRoot -Root $Dir
        if ($vs -and (Test-Path -LiteralPath (Join-Path $vs 'connect.ps1'))) {
            return (Test-GoodClientDir -Dir $vs)
        }
    }
    foreach ($n in @('connect.bat', 'connect.ps1', 'connect-update.ps1', 'cursor-proxy-sidecar.ps1', 'connect-version.txt', 'connect-heal.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $n))) { return $false }
    }
    try {
        $raw = Get-Content -LiteralPath (Join-Path $Dir 'connect-update.ps1') -Raw -ErrorAction Stop
        if ($raw -match 'UpdateEndpointTarget') { return $false }
    } catch { return $false }
    return $true
}

function Get-DirVersion {
    param([string]$Dir)
    try {
        if ($Dir -and (Split-Path -Leaf $Dir) -eq 'Claude-Connect') {
            $vs = Resolve-VersionedSrcUnderRoot -Root $Dir
            if ($vs) { return (Get-DirVersion -Dir $vs) }
            $cf = Join-Path $Dir 'current.txt'
            if (Test-Path -LiteralPath $cf) {
                $cv = (Get-Content -LiteralPath $cf -Raw -ErrorAction SilentlyContinue).Trim()
                if ($cv -match '^\d{8}\.\d+$') { return $cv }
            }
        }
        $vf = Join-Path $Dir 'connect-version.txt'
        if (-not (Test-Path -LiteralPath $vf)) { return '0' }
        $v = (Get-Content -LiteralPath $vf -TotalCount 1 -ErrorAction Stop).Trim()
        if ($v) { return $v }
    } catch {}
    return '0'
}

function Compare-Ver {
    param([string]$A, [string]$B)
    if ($A -eq $B) { return 0 }
    if ($A -match '^(\d{8})\.(\d+)$') {
        $ad = [int]$Matches[1]; $an = [int]$Matches[2]
        if ($B -match '^(\d{8})\.(\d+)$') {
            $bd = [int]$Matches[1]; $bn = [int]$Matches[2]
            if ($ad -ne $bd) { return [Math]::Sign($ad - $bd) }
            return [Math]::Sign($an - $bn)
        }
    }
    return [string]::CompareOrdinal($A, $B)
}

function Test-IsSepidzClientDir {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    if ($Dir -match '(?i)claude-code-sepidz|Claude-Connect-Sepidz') { return $true }
    $ps1 = Join-Path $Dir 'connect.ps1'
    if (-not (Test-Path -LiteralPath $ps1)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $ps1 -Raw -ErrorAction Stop
        # Match ONLY the $ServerIP assignment. Smart connect.ps1 also mentions
        # 192.168.250.70 in guard/compare code - a bare IP match false-positives Sepidz.
        if ($raw -match '(?m)^\s*\$ServerIP\s*=\s*[''"]192\.168\.250\.70[''"]') { return $true }
        if ($raw -match '(?m)^\s*\$ServerIP\s*=\s*[''"]192\.168\.210\.240[''"]') { return $false }
    } catch {}
    return $false
}

function Get-ServerTarget {
    if ($env:CLAUDE_UPDATE_SSH_TARGET) { return $env:CLAUDE_UPDATE_SSH_TARGET.Trim() }
    $ip = ''
    foreach ($base in @($Here, $Canon)) {
        if (-not $base) { continue }
        $p = Join-Path $base 'connect.ps1'
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $raw = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        $m = [regex]::Match($raw, '(?m)^\s*\$ServerIP\s*=\s*"([^"]+)"')
        if ($m.Success) { $ip = $m.Groups[1].Value.Trim(); break }
    }
    if (-not $ip) { $ip = '192.168.210.240' }
    # Prefer %USERPROFILE%\.config\claude-connect\connect.conf REMOTE_USER.
    # Site service user only if unset. Never force smart@ on 210.240.
    $user = ''
    $conf = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
    if (Test-Path -LiteralPath $conf) {
        foreach ($line in Get-Content -LiteralPath $conf -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*REMOTE_USER=(.+)$') {
                $user = $Matches[1].Trim().Trim('"').Trim("'")
                if ($user -and ($user -notmatch '[@/\\]')) { break }
                $user = ''
            }
        }
    }
    if (-not $user) {
        if ($ip -eq '192.168.250.70') { $user = 'sepidz' }
        elseif ($ip -eq '192.168.210.240') { $user = 'smart' }
        else { $user = 'smart' }
    }
    return ('{0}@{1}' -f $user, $ip)
}

function Invoke-SshTimed {
    param([string]$Exe, [string[]]$ArgumentList, [int]$TimeoutMs = 45000)
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outFile = Join-Path $env:TEMP ("claude-boot-$id.out")
    $errFile = Join-Path $env:TEMP ("claude-boot-$id.err")
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $ArgumentList -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return @{ Ok = $false; Out = ''; Err = 'timeout'; ExitCode = -1 }
        }
        Start-Sleep -Milliseconds 40
        $out = ''
        $err = ''
        try { if (Test-Path $outFile) { $out = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue } } catch {}
        try { if (Test-Path $errFile) { $err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue } } catch {}
        $ec = 0
        try { if ($null -ne $p.ExitCode) { $ec = [int]$p.ExitCode } } catch {}
        return @{ Ok = ($ec -eq 0); Out = [string]$out; Err = [string]$err; ExitCode = $ec }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
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

function Clear-LegacyFolderToExeOnly {
    # Publish/unzip folders must not keep a full client tree after redirect.
    # Leave only Claude-Connect.exe (+ tiny pointer readme) so users stop opening bat there.
    param(
        [Parameter(Mandatory)][string]$Dir,
        [string]$ExeSource = ''
    )
    if ([string]::IsNullOrWhiteSpace($Dir) -or -not (Test-Path -LiteralPath $Dir)) { return }
    try {
        $canonFull = [IO.Path]::GetFullPath($Canon)
        $dirFull = [IO.Path]::GetFullPath($Dir)
        if ([string]::Equals($dirFull, $canonFull, [StringComparison]::OrdinalIgnoreCase)) { return }
    } catch {}

    $exeName = 'Claude-Connect.exe'
    $keep = @{ $exeName = $true; 'READ-ME.txt' = $true }
    Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($keep.ContainsKey($_.Name)) { return }
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-BootLog ("legacy_clean_fail name=$($_.Name) err=$($_.Exception.Message)" -replace '[\r\n]', ' ') 'WARN'
        }
    }

    $dstExe = Join-Path $Dir $exeName
    $src = $ExeSource
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        $cand = @(
            (Join-Path $Canon $exeName),
            (Join-Path $env:USERPROFILE ('Desktop\' + $exeName))
        )
        foreach ($c in $cand) {
            if (Test-Path -LiteralPath $c) { $src = $c; break }
        }
    }
    if ($src -and (Test-Path -LiteralPath $src) -and (Test-ConnectExePeValid -Path $src)) {
        Copy-Item -LiteralPath $src -Destination $dstExe -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path -LiteralPath $dstExe) {
        if (-not (Test-ConnectExePeValid -Path $dstExe)) {
            Remove-Item -LiteralPath $dstExe -Force -ErrorAction SilentlyContinue
            Write-BootLog 'legacy_exe_removed_invalid_pe' 'WARN'
        }
    }

    $readme = @"
Claude Connect - do not run from this folder
===========================================
This publish/unzip folder is not the live client.

Use:
  Desktop\Claude-Connect.exe
or:
  Desktop\Claude-Connect\connect.bat
"@
    try {
        [IO.File]::WriteAllText((Join-Path $Dir 'READ-ME.txt'), ($readme -replace "`n", "`r`n"), [Text.UTF8Encoding]::new($false))
    } catch {}
    Write-BootLog ("legacy_cleaned_to_exe dir=$Dir")
}


function Copy-DirFiles {
    param([string]$Src, [string]$Dst, [string]$PreferVer = '')
    # Versioned root: install into Claude-Connect\{ver}\src — never flat-dump scripts at root.
    if ($Dst -and (Split-Path -Leaf $Dst) -eq 'Claude-Connect') {
        $ver = $PreferVer
        if ($ver -notmatch '^\d{8}\.\d+$') {
            try {
                $vf = Join-Path $Src 'connect-version.txt'
                if (Test-Path -LiteralPath $vf) {
                    $ver = (Get-Content -LiteralPath $vf -Raw -ErrorAction SilentlyContinue).Trim()
                }
            } catch { $ver = '' }
        }
        if ($ver -match '^\d{8}\.\d+$') {
            $verDir = Join-Path $Dst $ver
            $srcDir = Join-Path $verDir 'src'
            New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
            $Dst = $srcDir
            try {
                $rootForPtr = Split-Path -Parent (Split-Path -Parent $srcDir)
                if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
                    Set-ConnectInstallCurrent -Root $rootForPtr -Ver $ver
                }
            } catch {}
        } else {
            $vs = Resolve-VersionedSrcUnderRoot -Root $Dst
            if ($vs) { $Dst = $vs }
        }
    }
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    $n = 0
    foreach ($name in $PullNames) {
        if ($name -eq 'Claude-Connect.exe') { continue }
        $s = Join-Path $Src $name
        if (Test-Path -LiteralPath $s) {
            Copy-Item -LiteralPath $s -Destination (Join-Path $Dst $name) -Force
            $n++
        }
    }
    return $n
}

try {
    Clear-PreflightHandoff
    if ($Force) { Clear-RemoteVerDiskCache }
    if ($env:CLAUDE_CONNECT_SKIP_BOOTSTRAP -eq '1') {
        Write-BootLog 'skip reason=CLAUDE_CONNECT_SKIP_BOOTSTRAP=1'
        exit 0
    }
    if (-not (Get-Command scp -ErrorAction SilentlyContinue) -or -not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-BootLog 'ssh/scp missing - skip' 'WARN'
        Write-BootLog 'BOOTSTRAP_EXIT exit=1 reason=ssh_scp_missing' 'ERROR'
        exit 1
    }

    $legacy = $false
    if ($Here) {
        $legacy = ($Here -match '(?i)claude-code-client-\d{8}') -or ($Here -match '(?i)claude-code-sepidz-\d{8}') -or ($Here -match '(?i)[\\/]claude-publish[\\/]')
    }
    # Sepidz trees must never wipe/redirect to Desktop\Claude-Connect (Smart).
    if ($Here -and (Test-IsSepidzClientDir -Dir $Here)) {
        Write-BootLog ("sepidz_stay here=$Here")
        if (Test-GoodClientDir -Dir $Here) { exit 0 }
        Write-BootLog 'sepidz_here_bad skip_smart_canon_pull' 'WARN'
        Write-BootLog 'BOOTSTRAP_EXIT exit=1 reason=sepidz_here_bad' 'WARN'
        exit 1
    }
    $hereBad = $Here -and -not (Test-GoodClientDir -Dir $Here)
    $canonGood = Test-GoodClientDir -Dir $Canon
    $needPull = $Force -or (-not $canonGood) -or $hereBad -or $legacy

    $target = Get-ServerTarget
    Write-BootLog ("target_chosen=$target here=$Here force=$([bool]$Force) canon=$Canon")
    $canonVerEarly = Get-DirVersion -Dir $Canon
    $remoteVer = $null
    if (-not $Force -and $canonGood) {
        $remoteVer = Read-RemoteVerDiskCache -LocalVer $canonVerEarly
        if ($remoteVer) {
            Write-BootLog ("skip remote ver ssh cache hit ver=$remoteVer ttl_min=$RemoteVerCacheTtlMinutes")
        }
    }
    if (-not $remoteVer) {
        $cat = Invoke-SshTimed -Exe 'ssh' -ArgumentList ($SshOpts + @($target, "cat '$RemoteBundle/connect-version.txt'")) -TimeoutMs 15000
        if (-not $cat.Ok -or -not $cat.Out) {
            Write-BootLog ("ssh_fail target=$target err=$($cat.Err)" -replace '[\r\n]', ' ') 'ERROR'
            Write-BootLog ("BOOTSTRAP_EXIT exit=1 reason=ssh_fail target=$target") 'ERROR'
            exit 1
        }
        $remoteVer = ($cat.Out -split '\r?\n' | Select-Object -First 1).Trim()
        if (-not $remoteVer) {
            Write-BootLog 'empty remote version' 'ERROR'
            Write-BootLog 'BOOTSTRAP_EXIT exit=1 reason=empty_remote_version' 'ERROR'
            exit 1
        }
        if ($canonGood -and $canonVerEarly -eq $remoteVer) {
            Write-RemoteVerDiskCache -Ver $remoteVer
        } else {
            Clear-RemoteVerDiskCache
        }
    }

    $canonVer = Get-DirVersion -Dir $Canon
    if (-not $needPull -and $canonGood -and ((Compare-Ver -A $remoteVer -B $canonVer) -le 0)) {
        Write-BootLog ("skip canon already current ver=$canonVer remote=$remoteVer")
        if ($canonVer -eq $remoteVer) { Write-RemoteVerDiskCache -Ver $remoteVer }
        $hereHealthy = (-not $Here) -or (Test-GoodClientDir -Dir $Here)
        $handoff = @{
            SKIP_UPDATE = '1'
            REMOTE_VER  = $remoteVer
            LOCAL_VER   = $canonVer
        }
        if ($hereHealthy) { $handoff['SKIP_HEAL'] = '1' }
        Write-PreflightHandoff -Fields $handoff
        if ($Here -and $legacy -and -not [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)) {
            Clear-LegacyFolderToExeOnly -Dir $Here
            Set-Content -LiteralPath $RelaunchMarker -Value $Canon -Encoding ASCII
            Write-BootLog ("redirect legacy here=$Here") 'WARN'
            Write-BootLog ("BOOTSTRAP_EXIT exit=2 reason=redirect_legacy here=$Here canon=$Canon") 'WARN'
            exit 2
        }
        exit 0
    }

    Clear-RemoteVerDiskCache

    $stage = Join-Path $env:TEMP ('claude-client-bootstrap-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        Write-BootLog ("pull begin target=$target remote=$remoteVer")
        $remoteArgs = New-Object System.Collections.Generic.List[string]
        foreach ($o in $SshOpts) { [void]$remoteArgs.Add($o) }
        foreach ($name in $PullNames) {
            [void]$remoteArgs.Add(('{0}:{1}/{2}' -f $target, $RemoteBundle, $name))
        }
        [void]$remoteArgs.Add($stage)
        $scp = Invoke-SshTimed -Exe 'scp' -ArgumentList $remoteArgs.ToArray() -TimeoutMs 120000
        if (-not $scp.Ok) {
            Write-BootLog ("scp_fail exit=$($scp.ExitCode) err=$($scp.Err)" -replace '[\r\n]', ' ') 'ERROR'
            Write-BootLog ("BOOTSTRAP_EXIT exit=1 reason=scp_fail target=$target") 'ERROR'
            exit 1
        }
        if (-not (Test-GoodClientDir -Dir $stage)) {
            # staging may lack connect-bootstrap if older server; still require core update health
            $upd = Join-Path $stage 'connect-update.ps1'
            $core = (Test-Path (Join-Path $stage 'connect.bat')) -and (Test-Path (Join-Path $stage 'connect.ps1')) -and (Test-Path $upd) -and (Test-Path (Join-Path $stage 'cursor-proxy-sidecar.ps1'))
            $bug = $false
            if (Test-Path $upd) {
                $raw = Get-Content -LiteralPath $upd -Raw -ErrorAction SilentlyContinue
                if ($raw -match 'UpdateEndpointTarget') { $bug = $true }
            }
            if (-not $core -or $bug) {
                Write-BootLog 'stage incomplete or still broken update script' 'ERROR'
                Write-BootLog 'BOOTSTRAP_EXIT exit=1 reason=stage_incomplete' 'ERROR'
                exit 1
            }
        }
        $n = Copy-DirFiles -Src $stage -Dst $Canon -PreferVer $remoteVer
        Write-BootLog ("canon refreshed files=$n ver=$remoteVer dst=versioned_src")
        # Place EXE under VerDir + root alias; keep root clean.
        try {
            $verDir = Join-Path $Canon $remoteVer
            $destExe = Join-Path $verDir ("Claude-Connect-{0}.exe" -f $remoteVer)
            $stageExe = Join-Path $stage 'Claude-Connect.exe'
            New-Item -ItemType Directory -Force -Path $verDir | Out-Null
            if (Test-Path -LiteralPath $stageExe) {
                Copy-Item -LiteralPath $stageExe -Destination $destExe -Force -ErrorAction SilentlyContinue
                Copy-Item -LiteralPath $stageExe -Destination (Join-Path $Canon 'Claude-Connect.exe') -Force -ErrorAction SilentlyContinue
            }
            if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
                Set-ConnectInstallCurrent -Root $Canon -Ver $remoteVer
            }
            if (Get-Command Repair-ConnectRootLayout -ErrorAction SilentlyContinue) {
                [void](Repair-ConnectRootLayout -Root $Canon -Ver $remoteVer)
            } elseif (Get-Command Repair-ConnectAllVerDirLayouts -ErrorAction SilentlyContinue) {
                [void](Repair-ConnectAllVerDirLayouts -Root $Canon -Quiet)
            }
        } catch {
            Write-BootLog ("root_layout_warn $($_.Exception.Message)" -replace '[\r\n]', ' ') 'WARN'
        }
        if ($Here -and -not [string]::Equals($Here, $Canon, [StringComparison]::OrdinalIgnoreCase)) {
            if ($legacy -or $hereBad) {
                $stageExe = Join-Path $stage 'Claude-Connect.exe'
                Clear-LegacyFolderToExeOnly -Dir $Here -ExeSource $stageExe
                Set-Content -LiteralPath $RelaunchMarker -Value $Canon -Encoding ASCII
                Write-BootLog ("healed canon + cleaned legacy to EXE from=$Here") 'WARN'
                Write-BootLog ("BOOTSTRAP_EXIT exit=2 reason=healed_legacy_to_exe here=$Here canon=$Canon") 'WARN'
                exit 2
            }
        }
        exit 0
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    try { Write-BootLog (('FAIL ' + $_.Exception.Message) -replace '[\r\n]', ' ') 'ERROR' } catch {}
    try { Write-BootLog ('BOOTSTRAP_EXIT exit=1 reason=exception') 'ERROR' } catch {}
    exit 1
}
