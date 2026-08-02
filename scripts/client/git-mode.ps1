# git-mode.ps1 - shared GIT_MODE helpers (dot-sourced by connect.ps1 forks)
# Requires: $CfgDir, functions SshX, Test-Tunnel, Warn; $LaptopUser, $Port, $CM at call time
#
# Bundle co-origination stamp: must match connect.ps1 ConnectBuildId (publish bumps both).
# Detects split-generation installs where version string alone is unchanged (P1.2 residual).
$script:GitModeBuildId = '3ba70694-6390-4dc2-9e35-aadfb29d628e'

function Get-GitMode {
    # Site policy: GIT_MODE hide/server disabled. Always OFF (no .git rename).
    try {
        $gitConf = [System.IO.Path]::Combine($CfgDir, 'git.conf')
        if ($CfgDir) {
            if (-not (Test-Path $CfgDir)) { New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null }
            Set-Content -Path $gitConf -Value 'off' -Encoding ASCII -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
    return 'off'
}

function Get-GitModeLabel {
    param([string]$Mode = (Get-GitMode))
    switch ($Mode) {
        'server' { return 'SLOW' }
        'hide'   { return 'HIDE' }
        default  { return 'OFF' }
    }
}

function Write-GitModeLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'DEBUG'
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "GITMODE: $Message" $Level
    }
}

# Session-bound helper lifetime (DeferredSetup / MountBg / Windows-MCP ensure).
# Separate from the sidecar/tunnel KILL_ON_JOB_CLOSE job in cursor-proxy-sidecar.ps1:
# that job is deliberately kept alive across Connect exit (watchdog DuplicateHandle /
# keepTunnelForEditor). Helpers must die with THIS Connect process for ANY exit path
# (X button, crash, force-kill) and must not ride the surviving sidecar job.
$script:ConnectSessionJob = $null

function Initialize-ConnectSessionJob {
    if ($script:ConnectSessionJob) { return $true }
    try {
        if (-not ('ClaudeConnect.SessionJob' -as [type])) {
            Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ClaudeConnectSessionJob {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr hObject);
  [StructLayout(LayoutKind.Sequential)]
  public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
    public long PerProcessUserTimeLimit;
    public long PerJobUserTimeLimit;
    public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize;
    public UIntPtr MaximumWorkingSetSize;
    public uint ActiveProcessLimit;
    public UIntPtr Affinity;
    public uint PriorityClass;
    public uint SchedulingClass;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct IO_COUNTERS {
    public ulong ReadOperationCount;
    public ulong WriteOperationCount;
    public ulong OtherOperationCount;
    public ulong ReadTransferCount;
    public ulong WriteTransferCount;
    public ulong OtherTransferCount;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
    public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
    public IO_COUNTERS IoInfo;
    public UIntPtr ProcessMemoryLimit;
    public UIntPtr JobMemoryLimit;
    public UIntPtr PeakProcessMemoryUsed;
    public UIntPtr PeakJobMemoryUsed;
  }
  public const int JobObjectExtendedLimitInformation = 9;
  public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
  public static IntPtr CreateKillOnCloseJob() {
    IntPtr h = CreateJobObject(IntPtr.Zero, null);
    if (h == IntPtr.Zero) return IntPtr.Zero;
    var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
    IntPtr ptr = Marshal.AllocHGlobal(len);
    try {
      Marshal.StructureToPtr(info, ptr, false);
      if (!SetInformationJobObject(h, JobObjectExtendedLimitInformation, ptr, (uint)len)) {
        CloseHandle(h);
        return IntPtr.Zero;
      }
    } finally { Marshal.FreeHGlobal(ptr); }
    return h;
  }
}
"@
        }
        $h = [ClaudeConnectSessionJob]::CreateKillOnCloseJob()
        if ($h -eq [IntPtr]::Zero) { return $false }
        $script:ConnectSessionJob = $h
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SESSION_JOB created kill_on_close=1' 'INFO'
        }
        return $true
    } catch {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SESSION_JOB create_fail err={0}" -f $_.Exception.Message) 'WARN'
        }
        return $false
    }
}

function Add-ConnectSessionJobProcess {
    param([Parameter(Mandatory)]$Process)
    if (-not $Process) { return $false }
    if (-not (Initialize-ConnectSessionJob)) { return $false }
    try {
        # Touch .Handle early so PS 5.1 Start-Process -PassThru yields a usable handle.
        $null = $Process.Handle
        $ok = [ClaudeConnectSessionJob]::AssignProcessToJobObject(
            [IntPtr]$script:ConnectSessionJob,
            $Process.Handle
        )
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SESSION_JOB assign pid={0} ok={1}" -f $Process.Id, [int]$ok) 'DEBUG'
        }
        return [bool]$ok
    } catch {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SESSION_JOB assign_fail pid={0} err={1}" -f $Process.Id, $_.Exception.Message) 'DEBUG'
        }
        return $false
    }
}

function Stop-ConnectSessionJob {
    if (-not $script:ConnectSessionJob) { return }
    try {
        [void][ClaudeConnectSessionJob]::CloseHandle([IntPtr]$script:ConnectSessionJob)
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SESSION_JOB closed' 'INFO'
        }
    } catch {}
    $script:ConnectSessionJob = $null
}

function Start-JobBoundProcess {
    # Start-Process wrapper that assigns the child to the Connect session job object
    # (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE). When THIS Connect process exits for any reason,
    # Windows tears down every still-running job member. Fail-open on job create/assign:
    # the process still starts (same orphan risk as before, but Connect keeps working).
    # Do not declare an -ErrorAction param - it collides with PS common parameters.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateSet('Normal', 'Hidden', 'Minimized', 'Maximized')][string]$WindowStyle = 'Hidden',
        [string]$WorkingDirectory,
        [switch]$PassThru,
        [switch]$NoNewWindow
    )
    $spArgs = @{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        PassThru     = $true
        ErrorAction  = 'Stop'
    }
    if ($NoNewWindow) { $spArgs['NoNewWindow'] = $true }
    else { $spArgs['WindowStyle'] = $WindowStyle }
    if ($WorkingDirectory) { $spArgs['WorkingDirectory'] = $WorkingDirectory }
    $proc = Start-Process @spArgs
    if ($proc) {
        [void](Add-ConnectSessionJobProcess -Process $proc)
    }
    if ($PassThru) { return $proc }
    return
}

function Get-TunnelSessionDiagSuffix {
    $proj = if ($script:ActiveProjectId) { " project=$($script:ActiveProjectId)" } else { '' }
    return "${proj} soft_fail=$($script:TunnelSoftFailCount) sync_fail=$($script:TunnelSyncFailCount)"
}

function Write-TunnelDropLog {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [int]$TunnelPid = 0,
        [Nullable[bool]]$TcpOpen = $null,
        [Nullable[bool]]$TunnelUp = $null,
        [Nullable[bool]]$TunnelSyncOk = $null,
        [string]$Banner = $null,
        [string]$ProjectId = '',
        [bool]$EditorOpened = $false,
        [bool]$EditorSeen = $false,
        [int]$RecoveryGen = -1,
        [string]$DropCause = ''
    )
    if ($Reason -ne 'auto_reconnect') {
        $script:LastTunnelSyncDropReason = $Reason
    }
    if (-not $ProjectId -and $script:ActiveProjectId) { $ProjectId = [string]$script:ActiveProjectId }
    if (-not $ProjectId) { $ProjectId = '?' }
    if ($RecoveryGen -lt 0) { $RecoveryGen = [int]$script:RecoveryGeneration }
    if ($null -eq $TcpOpen) {
        try {
            if (Get-Command Test-TunnelPortTcpOpen -ErrorAction SilentlyContinue) {
                $TcpOpen = [bool](Test-TunnelPortTcpOpen)
            } else { $TcpOpen = $false }
        } catch { $TcpOpen = $false }
    }
    if ($null -eq $TunnelUp) {
        try {
            if (Get-Command Test-TunnelUp -ErrorAction SilentlyContinue) {
                $TunnelUp = [bool](Test-TunnelUp -Retries 1)
            } else { $TunnelUp = $false }
        } catch { $TunnelUp = $false }
    }
    if ($null -eq $TunnelSyncOk) { $TunnelSyncOk = $false }
    $cause = $DropCause
    if (-not $cause -and $Reason -eq 'auto_reconnect' -and $script:LastTunnelSyncDropReason) {
        $cause = [string]$script:LastTunnelSyncDropReason
    }
    $parts = @(
        'TUNNEL_DROP'
        "reason=$Reason"
        "soft_fail=$($script:TunnelSoftFailCount)"
        "sync_fail=$($script:TunnelSyncFailCount)"
        "tcp_open=$TcpOpen"
        "tunnel_up=$TunnelUp"
        "tunnel_sync_ok=$TunnelSyncOk"
        "project=$ProjectId"
        "editor_opened=$EditorOpened"
        "editor_seen=$EditorSeen"
        "gen=$RecoveryGen"
    )
    if ($Port) { $parts += "port=$Port" }
    if ($TunnelPid -gt 0) { $parts += "bg_pid=$TunnelPid" }
    if ($cause) { $parts += "drop_cause=$cause" }
    if ($null -ne $Banner) {
        $parts += "banner=$(if ($Banner) { $Banner } else { '(empty)' })"
    }
    $msg = $parts -join ' '
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog $msg 'WARN'
    } else {
        Write-GitModeLog $msg 'WARN'
    }
}

$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
$script:TunnelBannerCacheNegative = $false
$script:LastForwardProbeAt = $null
$script:TunnelMissCount = 0
$script:TunnelSyncFailCount = 0
$script:TunnelSoftFailCount = 0
$script:LastTunnelSpawnSuccessAt = $null
$script:LastTunnelSpawnSuccessPort = $null
$script:LastTunnelSpawnPid = $null
$script:LastTunnelExitLoggedPid = $null
$script:TunnelForwardProbeIntervalSec = 45
$script:TunnelSoftFailBudget = 4
$script:TunnelBannerDeferCount = 0
# Wait-ForTunnelUp iteration cap (was 12; storm fan-out). Locked by test-tunnel-wait-backoff-fanout.
if (-not $script:TunnelWaitMaxAttempts) { $script:TunnelWaitMaxAttempts = 6 }
# Still-busy refuse_spawn streak cap. Locked by test-stale-forward-rebind-streak.
if (-not $script:RefuseSpawnStreakCap) { $script:RefuseSpawnStreakCap = 5 }
$script:RefuseSpawnStreak = 0
# Owner/service coupling: release empty lease after backends-down + xray-expected.
# Locked by test-proxy-owner-service-coupling (S3 SERVICE_DEAD_SEC=60).
if (-not $script:ServiceDeadSec) { $script:ServiceDeadSec = 60 }
$script:ProxyOwnerServiceDeadSince = $null
$script:SessionEverHadProxyLegs = $false
$script:CursorProxyHealthNow = $null
# Sync no_proc keep-alive time-box (Task 5). Locked by test-tunnel-no-proc-keepalive (S3=120).
if (-not $script:NoProcZombieSec) { $script:NoProcZombieSec = 120 }
$script:NoProcKeepAliveSince = $null
$script:NoProcZombieNow = $null

function Clear-TunnelBannerCache {
    # WS4: CLAUDE_TUNNEL_BANNER_OK (sent to the server in Invoke-MountProject) is only ever
    # asserted from this cached, fresh, successful client-side banner probe - clearing it here
    # also invalidates that trust signal.
    $script:TunnelBannerCacheAt = $null
    $script:TunnelBannerCacheBanner = ''
    $script:TunnelBannerCacheUp = $false
    $script:TunnelBannerCacheNegative = $false
    $script:TunnelBannerCacheInvalidate = $true
    # Bug 51 companion: drop throttled ssh.exe CIM cache when tunnel state changes.
    $script:TunnelSshCimCache = $null
    $script:TunnelSshCimCacheAt = $null
    $script:TunnelSshCimCachePort = $null
}

function Test-LaptopRpathCompatible {
    param(
        [string]$Rpath,
        [ValidateSet('mac','windows')][string]$Os = 'windows'
    )
    if (-not $Rpath) { return $false }
    $p = $Rpath.Replace('\', '/').Trim()
    if ($Os -eq 'mac') {
        if ($p -match '^[A-Za-z]:') { return $false }
    } else {
        if ($p -match '^/Users/') { return $false }
    }
    return $true
}

function Test-LaptopRpathExists {
    param([string]$Rpath)
    if (-not $Rpath) { return $false }
    $p = $Rpath.Replace('\', '/').Trim()
    if ($p -match '^[A-Za-z]:$') { $p = "$p/" }
    return (Test-Path -LiteralPath $p)
}

function Get-LaptopRpathOsHint {
    param(
        [string]$Rpath,
        [ValidateSet('mac','windows')][string]$Os = 'windows'
    )
    if (Test-LaptopRpathCompatible -Rpath $Rpath -Os $Os) { return '' }
    if ($Os -eq 'mac') { return 'Windows only' }
    return 'Mac only'
}

function Warn-InvalidProjectRpath {
    param(
        [string]$Rpath,
        [string]$Num = '',
        [ValidateSet('mac','windows')][string]$Os = 'windows'
    )
    $suffix = if ($Num) { " Press e to edit project #$Num." } else { '' }
    if (-not (Test-LaptopRpathCompatible -Rpath $Rpath -Os $Os)) {
        if ($Os -eq 'mac') { Warn "Windows path - not usable on Mac.$suffix" }
        else { Warn "Mac path - not usable on Windows.$suffix" }
        return $false
    }
    if (-not (Test-LaptopRpathExists -Rpath $Rpath)) {
        $suffix2 = if ($Num) { " - press e to edit project #$Num." } else { '' }
        Warn "Folder not found on this laptop: $Rpath$suffix2"
        return $false
    }
    return $true
}

function Get-MountsForLaptop {
    param(
        [ValidateSet('mac','windows')][string]$Os = 'windows',
        [array]$Mounts = @()
    )
    if ($Mounts.Count -eq 0) { $Mounts = @(Get-Mounts) }
    return @($Mounts | Where-Object { Test-LaptopRpathCompatible -Rpath $_.Rpath -Os $Os })
}

function Get-SkippedMountCountForLaptop {
    param(
        [ValidateSet('mac','windows')][string]$Os = 'windows',
        [array]$Mounts = @()
    )
    if ($Mounts.Count -eq 0) { $Mounts = @(Get-Mounts) }
    return @($Mounts | Where-Object { -not (Test-LaptopRpathCompatible -Rpath $_.Rpath -Os $Os) }).Count
}

function Get-MountListStepLabel {
    param(
        [ValidateSet('mac','windows')][string]$Os = 'windows',
        [array]$Mounts = @()
    )
    if ($Mounts.Count -eq 0) { $Mounts = @(Get-Mounts) }
    $visible = @(Get-MountsForLaptop -Os $Os -Mounts $Mounts).Count
    $hidden = Get-SkippedMountCountForLaptop -Os $Os -Mounts $Mounts
    if ($hidden -gt 0) {
        if ($Os -eq 'mac') { return "$visible for this Mac ($hidden Windows-only hidden)" }
        return "$visible for this PC ($hidden Mac-only hidden)"
    }
    return "$visible project(s)"
}

function Read-PostDisconnectKey {
    param(
        [char]$DefaultChar = 'M',
        [int]$TimeoutSec = 10
    )
    Write-Host ''
    Write-Host '    Disconnected. What would you like to do?' -ForegroundColor Cyan
    Write-Host '    M = project menu   C = connect again   X = exit' -ForegroundColor DarkGray
    Write-Host ''

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $left = [math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($left -le $TimeoutSec -and $left -gt 0) {
            Write-Host "`r    Default $DefaultChar in ${left}s...   " -NoNewline -ForegroundColor DarkGray
        }
        if ([Console]::KeyAvailable) {
            Write-Host ''
            $ki = [Console]::ReadKey($true)
            $kcRaw = $ki.KeyChar.ToString()
            $code = if ($kcRaw.Length -eq 1) { [int][char]$kcRaw[0] } else { 0 }
            $ascii = ($code -ge 32 -and $code -le 126)
            $kc = if ($ascii) { $kcRaw.ToLowerInvariant() } else { '' }
            $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
            if ($kc -eq 'm' -or ($useVk -and $ki.Key -eq [ConsoleKey]::M)) { return 'm' }
            if ($kc -eq 'c' -or ($useVk -and $ki.Key -eq [ConsoleKey]::C)) { return 'c' }
            if ($kc -eq 'x' -or ($useVk -and $ki.Key -eq [ConsoleKey]::X)) { return 'x' }
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host ''
    Write-Host "    Default $DefaultChar" -ForegroundColor DarkGray
    return $DefaultChar.ToString().ToLower()
}

function Test-TunnelBannerIsTransportNoise {
    # SSH client / transport failure strings are NOT SSH banners. A real banner always
    # starts with SSH-2.0-. Mis-classifying transport text as "foreign banner" triggers
    # fuser -k over a dead link (SMART-LOG Incident A).
    param([string]$Banner)
    if (-not $Banner) { return $false }
    if ($Banner -match '^SSH-2\.0-') { return $false }
    return ($Banner -match '(?i)Unknown error|Connection timed out|Connection refused|Could not resolve|No route to host|Network is unreachable|Connection reset|Operation timed out|banner exchange|Connection closed|ssh:\s|timed out|Name or service not known')
}

function Get-TunnelBanner {
    param([int]$TargetPort = 0)
    $probePort = 0
    if ($TargetPort -gt 0) { $probePort = [int]$TargetPort }
    elseif (Get-Command Get-SessionTunnelPort -ErrorAction SilentlyContinue) { $probePort = [int](Get-SessionTunnelPort) }
    elseif ($Port) { $probePort = [int]$Port }
    if ($probePort -le 0) { return '' }
    # Positive cache (3s) OR brief negative cache (2s) — never re-probe a dead link every tick.
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($script:TunnelBannerCacheUp -and $ageMs -lt 3000) {
            Write-GitModeLog "TUNNEL_BANNER cache hit age_ms=$ageMs banner=$($script:TunnelBannerCacheBanner)" 'TRACE'
            return $script:TunnelBannerCacheBanner
        }
        if ($script:TunnelBannerCacheNegative -and -not $script:TunnelBannerCacheUp -and $ageMs -lt 2000) {
            Write-GitModeLog "TUNNEL_BANNER negative_cache hit age_ms=$ageMs port=$probePort" 'TRACE'
            return ''
        }
    }
    $script:TunnelBannerCacheInvalidate = $false
    Write-GitModeLog "TUNNEL_BANNER_BEGIN port=$probePort" 'TRACE'
    # Single TCP connection (read banner from same fd). Double /dev/tcp+nc burns 2 MaxStartups slots.
    $r = SshX "timeout 3 nc -w 2 127.0.0.1 $probePort 2>/dev/null | head -1" 2>$null
    $banner = (($r -join '') -replace "`r",'').Trim()
    if ($banner -match 'MaxStartups') {
        Write-GitModeLog "TUNNEL_BANNER soft_fail port=$probePort reason=maxstartups" 'WARN'
        $banner = ''
    }
    if ($banner -and (Test-TunnelBannerIsTransportNoise -Banner $banner)) {
        Write-GitModeLog "TUNNEL_BANNER transport_fail port=$probePort detail=$banner" 'DEBUG'
        $banner = ''
        $script:TunnelBannerCacheAt = Get-Date
        $script:TunnelBannerCacheBanner = ''
        $script:TunnelBannerCacheUp = $false
        $script:TunnelBannerCacheNegative = $true
        $script:TunnelMissCount = [int]$script:TunnelMissCount + 1
        Write-GitModeLog "TUNNEL_BANNER port=$probePort banner=" 'DEBUG'
        return ''
    }
    $up = (Test-TunnelBannerIsWindows -Banner $banner)
    if ($up) {
        $script:TunnelBannerCacheAt = Get-Date
        $script:TunnelBannerCacheBanner = $banner
        $script:TunnelBannerCacheUp = $true
        $script:TunnelBannerCacheNegative = $false
        $script:TunnelMissCount = 0
    } else {
        # Do NOT negative-cache ordinary empty/miss (poisoned DROP1 recovery). Transport
        # failures already set TunnelBannerCacheNegative above.
        $script:TunnelBannerCacheAt = $null
        $script:TunnelBannerCacheBanner = ''
        $script:TunnelBannerCacheUp = $false
        $script:TunnelBannerCacheNegative = $false
        $script:TunnelMissCount = [int]$script:TunnelMissCount + 1
        Write-GitModeLog "TUNNEL_BANNER miss=$($script:TunnelMissCount) port=$probePort banner=$banner" 'DEBUG'
    }
    Write-GitModeLog "TUNNEL_BANNER port=$probePort banner=$banner" 'DEBUG'
    return $banner
}

function Test-TunnelBannerIsWindows {
    param([string]$Banner)
    if (-not $Banner) { return $false }
    if (Test-TunnelBannerIsTransportNoise -Banner $Banner) { return $false }
    if ($Banner -notmatch '^SSH-2\.0-') { return $false }
    return ($Banner -match 'OpenSSH_for_Windows')
}

function Test-TunnelBannerIsThisLaptop {
    param([string]$Banner)
    # NOTE: OpenSSH_for_Windows is shared by all Windows peers. Prefer Test-TunnelPortIsForeignPeer /
    # Test-TunnelPortAuthOwned for ownership. Kept for banner-shape checks and Test-TunnelUp.
    if (-not $Banner) { $Banner = Get-TunnelBanner }
    return (Test-TunnelBannerIsWindows -Banner $Banner)
}

function Save-TunnelSlot {
    if (-not $Cfg) { return }
    $lines = @()
    if (Test-Path $Cfg) {
        $lines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object {
            $_ -notmatch '^(TUNNEL_SLOT|PORT|TUNNEL_PORT)='
        })
    }
    $lines += "TUNNEL_SLOT=$($script:TunnelSlot)"
    if ($script:Port) {
        $lines += "PORT=$($script:Port)"
        $lines += "TUNNEL_PORT=$($script:Port)"
    }
    Set-Content -Path $Cfg -Value $lines -Encoding ASCII
}


function Get-SessionTunnelPort {
    if ($null -ne $script:Port -and [int]$script:Port -gt 0) { return [int]$script:Port }
    if ($Port -and [int]$Port -gt 0) { return [int]$Port }
    return 0
}



function Get-SshConfigWriteMutex {
    # Cross-process serializer for ~/.ssh/config read-modify-write (multi Connect UI /
    # click-storm). 'Local\' is the per-logon-session namespace: UAC elevation keeps the same
    # session id, so an elevated -AdminFix instance and the plain UI share this mutex.
    # 'Global\' needs SeCreateGlobalPrivilege (stripped from a filtered admin token) and would
    # split elevated vs non-elevated writers into two disjoint locks - so it is only a fallback.
    if ($script:SshConfigWriteMutex) { return $script:SshConfigWriteMutex }
    foreach ($name in @('Local\ClaudeConnectSshConfigWrite', 'Global\ClaudeConnectSshConfigWrite')) {
        try {
            $created = $false
            $script:SshConfigWriteMutex = New-Object System.Threading.Mutex($false, $name, [ref]$created)
            return $script:SshConfigWriteMutex
        } catch { }
    }
    return $null
}

function Invoke-WithSshConfigLock {
    # Fail-open: if the mutex cannot be created or is abandoned we still run the action, which
    # keeps its own retry loop. Never let lock trouble turn into an UNHANDLED crash.
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$TimeoutMs = 15000
    )
    $mtx = Get-SshConfigWriteMutex
    $owned = $false
    try {
        if ($mtx) {
            try { $owned = $mtx.WaitOne($TimeoutMs) }
            catch [System.Threading.AbandonedMutexException] { $owned = $true }
            catch { $owned = $false }
        }
        return & $Action
    } finally {
        if ($owned -and $mtx) { try { $mtx.ReleaseMutex() } catch { } }
    }
}

function Write-AsciiFileRetry {
    # Atomic write with retries for files sshd/ssh may briefly lock (e.g. ~/.ssh/config).
    # File.Replace/Move swap the fully written temp file in as a single rename, so a concurrent
    # ssh.exe never observes a truncated config; Replace also preserves the destination ACL that
    # Repair-SshPerm / icacls set on ~/.ssh/config.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value,
        [int]$Retries = 8
    )
    $text = if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        (($Value | ForEach-Object { [string]$_ }) -join "`r`n") + "`r`n"
    } else {
        [string]$Value
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Force -Path $dir
    }
    $tmp = "$Path.write.$PID.$([guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
    $last = $null
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            [System.IO.File]::WriteAllText($tmp, $text, [System.Text.Encoding]::ASCII)
            if (Test-Path -LiteralPath $Path) {
                # [NullString]::Value, not $null: PS coerces $null to '' for [string] parameters
                # and Replace then fails with "The path is not of a legal form".
                [System.IO.File]::Replace($tmp, $Path, [NullString]::Value, $true)
            } else {
                [System.IO.File]::Move($tmp, $Path)
            }
            return
        } catch {
            $last = $_.Exception.Message
            if ($i -eq $Retries) {
                # Last resort: a non-atomic copy still beats throwing an UNHANDLED at the caller.
                try { Copy-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop; return }
                catch { $last = $_.Exception.Message }
            }
            Start-Sleep -Milliseconds (80 * $i)
        } finally {
            if (Test-Path -LiteralPath $tmp) {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
    throw "Write-AsciiFileRetry failed path=$Path err=$last"
}

function Sanitize-SshAliasConfig {
    param(
        [Parameter(Mandatory)][string]$CfgPath,
        [string]$AliasName = 'claude-server'
    )
    if (-not (Test-Path $CfgPath)) { return }
    # Mutex is reentrant per thread, so nesting inside Set-SshHostBlock's lock is safe.
    Invoke-WithSshConfigLock -Action {
        if (-not (Test-Path -LiteralPath $CfgPath)) { return }
        $out = New-Object System.Collections.Generic.List[string]
        $skip = $false
        foreach ($ln in @(Get-Content -LiteralPath $CfgPath -ErrorAction SilentlyContinue)) {
            if ($ln -match '^\s*Host\s+(.+)$') {
                $hosts = $matches[1].Trim() -split '\s+'
                $skip = ($hosts -contains $AliasName)
            }
            if ($skip -and $ln -match '^\s*RemoteForward\b') { continue }
            $out.Add($ln)
        }
        Write-AsciiFileRetry -Path $CfgPath -Value $out
    }
}

# Short-TTL cache of remote loopback tcp-open verdicts per port. The acquire batch probe
# (Get-ServerOpenTunnelPorts) already learns the open/closed state of every candidate port in ONE
# ssh; the very same port is then re-probed moments later by the push-conf safety gate and the
# ENSURE_TUNNEL stale-forward check - each a fresh ~1.4s one-shot ssh (no ControlMaster on
# Windows). Opt-in callers (-MaxCacheAgeMs) reuse the batch verdict when it is only seconds old.
# TTL is kept short and only trusted by pre-spawn checks: we ourselves spawn a listener on the
# chosen port during the same connect, and the port sits inside our own non-overlapping UID block
# (so nobody else claims it in the few-second window). Polling/wait loops pass no MaxCacheAgeMs and
# therefore always probe fresh.
$script:TunnelTcpStateCache = @{}

function Set-TunnelTcpState {
    param([Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][bool]$Open)
    if ($Port -le 0) { return }
    if (-not $script:TunnelTcpStateCache) { $script:TunnelTcpStateCache = @{} }
    $script:TunnelTcpStateCache[[string]$Port] = @{ Open = $Open; At = (Get-Date) }
}

function Clear-TunnelTcpState {
    param([int]$Port = 0)
    if (-not $script:TunnelTcpStateCache) { return }
    if ($Port -gt 0) { $script:TunnelTcpStateCache.Remove([string]$Port) | Out-Null }
    else { $script:TunnelTcpStateCache.Clear() }
}

function Test-TunnelPortTcpOpen {
    param([int]$TargetPort = 0, [int]$MaxCacheAgeMs = 0)
    $probePort = 0
    if ($TargetPort -gt 0) { $probePort = [int]$TargetPort }
    elseif (Get-Command Get-SessionTunnelPort -ErrorAction SilentlyContinue) { $probePort = [int](Get-SessionTunnelPort) }
    elseif ($Port) { $probePort = [int]$Port }
    if ($probePort -le 0) { return $false }
    if ($MaxCacheAgeMs -gt 0 -and $script:TunnelTcpStateCache -and $script:TunnelTcpStateCache.ContainsKey([string]$probePort)) {
        $e = $script:TunnelTcpStateCache[[string]$probePort]
        if ($e -and ((Get-Date) - $e.At).TotalMilliseconds -lt $MaxCacheAgeMs) {
            Write-GitModeLog "TCP_STATE cache_hit port=$probePort open=$($e.Open)" 'TRACE'
            return [bool]$e.Open
        }
    }
    $r = SshX "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$probePort 2>/dev/null' && echo open || echo closed" 2>$null
    $out = (($r -join '') -replace "`r",'').Trim()
    $isOpen = ($out -eq 'open')
    Set-TunnelTcpState -Port $probePort -Open $isOpen
    return $isOpen
}

function Test-TunnelPortTcpOpenAndScanHostKey {
    param([Parameter(Mandatory)][int]$TargetPort)
    # Perf (H12): fold the tcp-open re-check (normally Test-TunnelPortTcpOpen) and the
    # ssh-keyscan hostkey fingerprint scan (normally Get-TunnelHostKeyFingerprint) into
    # ONE SSH round trip instead of two (~1.2-1.6s of pure SSH-exec overhead each on
    # Windows - see Invoke-SshXCore comment, no ControlMaster mux available here). The
    # remote script only runs ssh-keyscan when the tcp probe itself succeeded, so this
    # never adds latency to the "port is closed" case (identical to calling
    # Test-TunnelPortTcpOpen alone) - it only removes a second full SSH handshake for
    # the common "port open, caller also needs the hostkey" case. Only call this when
    # the caller already knows it will need BOTH values (see Test-TunnelPortIsForeignPeer).
    $scriptBody = @"
if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TargetPort" 2>/dev/null; then
  echo TCP:open
  FP=`$(timeout 4 ssh-keyscan -p $TargetPort -T 3 -t ed25519,rsa,ecdsa 127.0.0.1 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print `$2}' | head -1)
  echo "HOSTKEY:`$FP"
else
  echo TCP:closed
fi
"@
    # Bash remote payloads must be LF-only: Windows CRLF in here-strings breaks `bash -c`.
    $scriptBody = (($scriptBody -replace "`r`n", "`n") -replace "`r", "`n")
    $out = @(SshX $scriptBody 2>$null)
    $tcpLine = ($out | Where-Object { $_ -match '^TCP:' } | Select-Object -First 1)
    $tcpOpen = [bool]($tcpLine -match '^TCP:open')
    if ($tcpOpen) {
        $hkLine = ($out | Where-Object { $_ -match '^HOSTKEY:' } | Select-Object -First 1)
        $fp = ''
        if ($hkLine -match '^HOSTKEY:(.*)$') {
            $fp = (($Matches[1] -replace "`r", '') -replace '\s', '').Trim()
            if ($fp -and $fp -notmatch '^(SHA256:|MD5:)') { $fp = '' }
        }
        if (-not $script:TunnelHostKeyFpByPort) { $script:TunnelHostKeyFpByPort = @{} }
        $script:TunnelHostKeyFpByPort[[string]$TargetPort] = $fp
        if ($fp) { Write-GitModeLog "HOSTKEY_FP scan port=$TargetPort fp=$fp" 'DEBUG' }
    }
    return $tcpOpen
}

# Still-busy spawn abort window (Clear -> Ensure race). Locked by test-stale-forward-wait-init.
if (-not $script:StillBusyWindowSec) { $script:StillBusyWindowSec = 15 }
$script:LastStaleForwardStillBusyPort = $null
$script:LastStaleForwardStillBusyAt = $null

function Clear-ServerStaleTunnelForward {
    param([int]$TargetPort = $Port)
    if (-not $TargetPort) { return }
    # Never fuser-kill another laptop's reverse tunnel.
    if (Get-Command Test-TunnelPortIsForeignPeer -ErrorAction SilentlyContinue) {
        if (Test-TunnelPortIsForeignPeer -TargetPort $TargetPort) {
            Write-GitModeLog "STALE_FORWARD: refuse_kill_foreign port=$TargetPort" 'WARN'
            return
        }
    }
    if (Get-Command Test-TunnelHostKeyMismatch -ErrorAction SilentlyContinue) {
        if (Test-TunnelHostKeyMismatch -TargetPort $TargetPort) {
            Write-GitModeLog "STALE_FORWARD: refuse_kill_hostkey_mismatch port=$TargetPort" 'WARN'
            return
        }
    }
    Write-GitModeLog "STALE_FORWARD: clearing server port=$TargetPort" 'DEBUG'
    SshX "fuser -k ${TargetPort}/tcp 2>/dev/null || true; pkill -u `$USER -f '127\\.0\\.0\\.1:${TargetPort}' 2>/dev/null || true; pkill -u `$USER -f ' -p ${TargetPort} ' 2>/dev/null || true" 2>$null | Out-Null
    Clear-TunnelBannerCache
    Clear-TunnelAuthOwnedCache -TargetPort $TargetPort
    # Keep short: long waits were a major "still slow" cost when ports were sticky.
    for ($i = 1; $i -le 4; $i++) {
        Start-Sleep -Milliseconds 250
        Clear-TunnelBannerCache
        if (-not (Test-TunnelPortTcpOpen -TargetPort $TargetPort)) {
            Write-GitModeLog "STALE_FORWARD: port released port=$TargetPort wait=$i" 'DEBUG'
            Add-ClearedTunnelPort -TargetPort $TargetPort
            $script:LastStaleForwardStillBusyPort = $null
            $script:LastStaleForwardStillBusyAt = $null
            return
        }
    }
    $script:LastStaleForwardStillBusyPort = [int]$TargetPort
    $script:LastStaleForwardStillBusyAt = Get-Date
    Write-GitModeLog "STALE_FORWARD: port still busy port=$TargetPort after wait" 'WARN'
}

function Test-StaleForwardStillBusyAbort {
    param([int]$TargetPort = $Port)
    if (-not $TargetPort) { return $false }
    if ($null -eq $script:LastStaleForwardStillBusyPort) { return $false }
    if ([int]$script:LastStaleForwardStillBusyPort -ne [int]$TargetPort) { return $false }
    if (-not $script:LastStaleForwardStillBusyAt) { return $false }
    $windowSec = 15
    if ($script:StillBusyWindowSec) { $windowSec = [int]$script:StillBusyWindowSec }
    $age = ((Get-Date) - $script:LastStaleForwardStillBusyAt).TotalSeconds
    if ($age -ge $windowSec) { return $false }
    $tcpOpen = $false
    try { $tcpOpen = [bool](Test-TunnelPortTcpOpen -TargetPort $TargetPort) } catch { $tcpOpen = $false }
    if (-not $tcpOpen) { return $false }
    $localCount = @(Get-LocalTunnelSshPids -TargetPort $TargetPort).Count
    if ($localCount -gt 0) { return $false }
    return $true
}

function Release-StaleTunnelPort {
    if (-not $Port) { return }
    Clear-TunnelBannerCache
    $banner = Get-TunnelBanner
    # Windows banner alone is not "ours" (peer laptops look identical). Only reclaim when owned.
    if ($banner -and (Test-TunnelBannerIsWindows -Banner $banner)) {
        $localPids = @(Get-LocalTunnelSshPids -TargetPort $Port)
        if ($localPids.Count -gt 0) { return }
        if (Test-TunnelPortAuthOwned -TargetPort $Port) {
            Write-GitModeLog "STALE_FORWARD: sticky_ours port=$Port reclaim" 'DEBUG'
            Clear-ServerStaleTunnelForward -TargetPort $Port
            return
        }
        Write-GitModeLog "STALE_FORWARD: skip_foreign_peer port=$Port banner=$banner" 'INFO'
        return
    }
    if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) {
        # Transport/timeout strings are not foreign sshd banners — do not fuser-kill.
        if (Test-TunnelBannerIsTransportNoise -Banner $banner) {
            Write-GitModeLog "STALE_FORWARD: transport_fail skip_foreign_clear port=$Port banner=$banner" 'DEBUG'
            return
        }
        Write-GitModeLog "STALE_FORWARD: foreign banner port=$Port banner=$banner" 'DEBUG'
        Clear-ServerStaleTunnelForward -TargetPort $Port
        return
    }
    if (Test-TunnelPortTcpOpen) {
        if (Test-TunnelPortIsForeignPeer -TargetPort $Port) {
            Write-GitModeLog "STALE_FORWARD: skip_foreign_peer port=$Port tcp=open" 'INFO'
            return
        }
        Write-GitModeLog "STALE_FORWARD: zombie port=$Port tcp=open banner=(empty)" 'WARN'
        Clear-ServerStaleTunnelForward -TargetPort $Port
    }
}

function Get-TunnelProcessExitCode {
    param([System.Diagnostics.Process]$Process)
    if (-not $Process) { return 'unavailable' }
    try {
        $Process.Refresh()
        if ($Process.HasExited) { return [string]$Process.ExitCode }
    } catch { }
    return 'unavailable'
}

function Stop-TunnelProcessWithExitLog {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$Reason
    )
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-GitModeLog "TUNNEL_EXIT pid=$ProcessId port=$Port exit_code=unavailable reason=$Reason state=not_found" 'DEBUG'
        return
    }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        try { $null = $proc.WaitForExit(1000) } catch { }
        $exitCode = Get-TunnelProcessExitCode -Process $proc
        Write-GitModeLog "TUNNEL_EXIT pid=$ProcessId port=$Port exit_code=$exitCode reason=$Reason" 'DEBUG'
    } catch {
        Write-GitModeLog "TUNNEL_EXIT pid=$ProcessId port=$Port exit_code=unavailable reason=$Reason stop_error=$($_.Exception.Message)" 'WARN'
    }
}

function Get-LocalTunnelSshReverseRegex {
    param([Parameter(Mandatory)][int]$TargetPort)
    $portEsc = [regex]::Escape("$TargetPort")
    return "-R(?:\s*=\s*|\s+)${portEsc}:(?:localhost|127\.0\.0\.1):22\b"
}

function Test-LocalTunnelSshCommandLine {
    param(
        [string]$CommandLine,
        [Parameter(Mandatory)][int]$TargetPort
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    if ($CommandLine -match '(?i)ssh-keygen') { return $false }
    return [bool]($CommandLine -match (Get-LocalTunnelSshReverseRegex -TargetPort $TargetPort))
}

function Get-LocalTunnelSshReversePortFromCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    if ($CommandLine -match '-R(?:\s*=\s*|\s+)(\d+):(?:localhost|127\.0\.0\.1):22\b') {
        return [int]$Matches[1]
    }
    return $null
}

function Get-LocalTunnelSshPids {
    param([Parameter(Mandatory)][int]$TargetPort)
    $pids = @()
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { Test-LocalTunnelSshCommandLine -CommandLine $_.CommandLine -TargetPort $TargetPort } |
        ForEach-Object { $pids += [int]$_.ProcessId }
    return @($pids | Select-Object -Unique)
}

# Peer safety: kill stale local ssh -R on this port only; never the live session PID
# (ORPHAN_TUNNEL: skip_current / skip_sibling). Never kill another Connect UI's -R.

function Test-ProcessCommandIsConnectUi {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    return [bool]($CommandLine -match '(?i)((^|[\\/])connect-boot\.ps1|(^|[\\/])connect\.ps1)')
}

function Get-SiblingConnectTunnelPids {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [int[]]$ProtectedProcessIds = @()
    )
    $protected = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($p in @($ProtectedProcessIds)) {
        if ($null -ne $p) { [void]$protected.Add([int]$p) }
    }
    if ($PID) { [void]$protected.Add([int]$PID) }
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        [void]$protected.Add([int]$script:SessionBgTunnel.Id)
    }
    $siblings = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($sshPid in @(Get-LocalTunnelSshPids -TargetPort $TargetPort)) {
        $sshPid = [int]$sshPid
        if ($protected.Contains($sshPid)) { continue }
        $cur = $sshPid
        $hops = 0
        $isSibling = $false
        while ($cur -gt 0 -and $hops -lt 14) {
            $hops++
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
            if (-not $cim) { break }
            $cmd = [string]$cim.CommandLine
            if (Test-ProcessCommandIsConnectUi -CommandLine $cmd) {
                $uiPid = [int]$cim.ProcessId
                if ($uiPid -eq [int]$PID -or $protected.Contains($uiPid)) { break }
                $isSibling = $true
                break
            }
            $parent = [int]$cim.ParentProcessId
            if ($parent -le 0 -or $parent -eq $cur) { break }
            $cur = $parent
        }
        if ($isSibling) { [void]$siblings.Add($sshPid) }
    }
    return @($siblings)
}

function Test-IsPrimaryTunnelPublisher {
    # Slot preference only: UI slot 0 (or legacy unset) is the preferred publisher.
    # Push-ServerConnectConf's remote AM_ONLY body may still let a non-primary publish
    # when the currently-published port is confirmed dead and this session's port is
    # confirmed listening (P1.3 liveness override -- see port_takeover).
    $slot = ($env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
    if ($slot -eq '') { return $true }
    return ($slot -eq '0')
}

function Remove-LocalOrphanTunnel {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    # Hybrid multi-UI: peer Connects bind base+UI_SLOT. Never kill a sibling's live ssh -R
    # (ORPHAN_TUNNEL: skip_sibling). True orphans (no Connect UI ancestor) may be reclaimed.
    $protected = @($ProtectedProcessIds)
    if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) {
        $protected += [int]$CurrentBgTunnel.Id
    }
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $protected += [int]$script:SessionBgTunnel.Id
    }
    $siblings = @()
    if (Get-Command Get-SiblingConnectTunnelPids -ErrorAction SilentlyContinue) {
        $siblings = @(Get-SiblingConnectTunnelPids -TargetPort $TargetPort -ProtectedProcessIds $protected)
        if ($siblings.Count -gt 0) {
            $protected = @($protected + $siblings | Select-Object -Unique)
        }
    }
    $killed = $false
    foreach ($processId in (Get-LocalTunnelSshPids -TargetPort $TargetPort)) {
        if ($protected -contains $processId) {
            if ($siblings -contains $processId) {
                Write-GitModeLog "ORPHAN_TUNNEL: skip_sibling pid=$processId port=$TargetPort" 'INFO'
            } else {
                Write-GitModeLog "ORPHAN_TUNNEL: skip_current pid=$processId port=$TargetPort" 'DEBUG'
            }
            continue
        }
        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($proc -and -not $proc.HasExited) {
            Write-GitModeLog "ORPHAN_TUNNEL: kill pid=$processId port=$TargetPort reason=unprotected_live" 'INFO'
            Stop-TunnelProcessWithExitLog -ProcessId $processId -Reason 'orphan_cleanup'
            $killed = $true
            continue
        }
        Write-GitModeLog "ORPHAN_TUNNEL: skip_stale pid=$processId port=$TargetPort reason=not_live" 'DEBUG'
    }
    if ($killed) { Clear-TunnelBannerCache }
    return $true
}

function Get-ConnectUiPidForProcess {
    param([Parameter(Mandatory)][int]$StartProcessId)
    $cur = [int]$StartProcessId
    $hops = 0
    while ($cur -gt 0 -and $hops -lt 14) {
        $hops++
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
        if (-not $cim) { break }
        if (Test-ProcessCommandIsConnectUi -CommandLine ([string]$cim.CommandLine)) {
            return [int]$cim.ProcessId
        }
        $parent = [int]$cim.ParentProcessId
        if ($parent -le 0 -or $parent -eq $cur) { break }
        $cur = $parent
    }
    return 0
}

function Get-ConnectSessionSlotMarkerDir {
    if ($CfgDir) { return $CfgDir }
    return (Join-Path $env:USERPROFILE '.config\claude-connect')
}

function Get-ConnectSessionSlotMarkerPath {
    param([Parameter(Mandatory)][int]$Slot)
    return (Join-Path (Get-ConnectSessionSlotMarkerDir) ("session-slot-{0}.json" -f $Slot))
}

function Write-ConnectSessionSlotMarker {
    param(
        [Parameter(Mandatory)][int]$Slot,
        [Parameter(Mandatory)][int]$Port,
        [string]$ProjectId = '',
        [string]$RemotePath = '',
        [int]$ProcessId = 0
    )
    try {
        $dir = Get-ConnectSessionSlotMarkerDir
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $markerPid = if ($ProcessId -gt 0) { $ProcessId } else { [int]$PID }
        $obj = [ordered]@{
            pid        = $markerPid
            slot       = $Slot
            port       = $Port
            projectId  = ($ProjectId + '').Trim()
            remotePath = ($RemotePath + '').Trim()
            updated    = (Get-Date).ToString('o')
        }
        $json = ($obj | ConvertTo-Json -Compress)
        # UTF-8 without BOM: Windows PowerShell 5.1 ConvertFrom-Json often fails on BOM.
        $path = Get-ConnectSessionSlotMarkerPath -Slot $Slot
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-GitModeLog ("HYGIENE_MARKER_WRITE_FAIL slot={0} err={1}" -f $Slot, $_.Exception.Message) 'WARN'
    }
}

function Clear-ConnectSessionSlotMarker {
    param([int]$Slot = -1)
    try {
        if ($Slot -ge 0) {
            $p = Get-ConnectSessionSlotMarkerPath -Slot $Slot
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
            return
        }
        $slotEnv = ($env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
        if ($slotEnv -match '^\d+$') {
            Clear-ConnectSessionSlotMarker -Slot ([int]$slotEnv)
        }
    } catch { }
}

function Get-ConnectSessionSlotMarkers {
    # Use List + foreach (not ForEach-Object + $out +=): in Windows PowerShell 5.1,
    # `$out +=` inside ForEach-Object often binds a *local* $out and leaves the outer empty.
    $out = New-Object 'System.Collections.Generic.List[object]'
    $dir = Get-ConnectSessionSlotMarkerDir
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'session-slot-*.json' -ErrorAction SilentlyContinue)) {
        try {
            $raw = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
            $o = $raw | ConvertFrom-Json
            # Never name this $pid — PowerShell aliases it to read-only automatic $PID.
            $markerPid = [int]$o.pid
            $alive = $false
            if ($markerPid -gt 0) {
                $pr = Get-Process -Id $markerPid -ErrorAction SilentlyContinue
                if ($pr) {
                    try { $alive = -not $pr.HasExited } catch { $alive = $true }
                }
            }
            if (-not $alive) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                continue
            }
            [void]$out.Add([pscustomobject]@{
                Pid        = $markerPid
                Slot       = [int]$o.slot
                Port       = [int]$o.port
                ProjectId  = [string]$o.projectId
                RemotePath = [string]$o.remotePath
                IsCurrent  = ($markerPid -eq [int]$PID)
            })
        } catch { }
    }
    return @($out.ToArray())
}

function Get-ConnectHygieneReport {
    param(
        [string]$UidStr = '',
        [string]$ProtectRemotePath = '',
        [string]$ProtectProjectId = '',
        [switch]$SkipServer
    )
    Write-GitModeLog 'HYGIENE_SCAN begin' 'INFO'
    $base = 20000
    if ($UidStr -and (Get-Command Get-TunnelPortUserBase -ErrorAction SilentlyContinue)) {
        $base = [int](Get-TunnelPortUserBase -UidStr $UidStr)
    }
    $currentTunnelPid = 0
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $currentTunnelPid = [int]$script:SessionBgTunnel.Id
    }
    $markers = @(Get-ConnectSessionSlotMarkers)
    $tunnels = @()
    $orphanPids = @()
    $siblingEntries = @()
    for ($slot = 0; $slot -lt 10; $slot++) {
        $port = $base + $slot
        foreach ($sshPid in @(Get-LocalTunnelSshPids -TargetPort $port)) {
            $sshPid = [int]$sshPid
            $uiPid = Get-ConnectUiPidForProcess -StartProcessId $sshPid
            $class = 'orphan'
            if ($sshPid -eq $currentTunnelPid -or $uiPid -eq [int]$PID) {
                $class = 'current'
            } elseif ($uiPid -gt 0 -and $uiPid -ne [int]$PID) {
                $class = 'sibling'
            }
            $mark = @($markers | Where-Object { $_.Port -eq $port -or $_.Pid -eq $uiPid } | Select-Object -First 1)
            $projectId = if ($mark) { [string]$mark.ProjectId } else { '' }
            $remotePath = if ($mark) { [string]$mark.RemotePath } else { '' }
            $row = [pscustomobject]@{
                Port       = $port
                Slot       = $slot
                TunnelPid  = $sshPid
                ConnectUiPid = $uiPid
                Class      = $class
                ProjectId  = $projectId
                RemotePath = $remotePath
            }
            $tunnels += $row
            if ($class -eq 'orphan') { $orphanPids += $sshPid }
            if ($class -eq 'sibling') { $siblingEntries += $row }
        }
    }
    $protectRoot = ''
    if ($ProtectRemotePath) {
        $protectRoot = [System.IO.Path]::GetFileName(($ProtectRemotePath.TrimEnd('/','\')))
    } elseif ($ProtectProjectId) {
        $protectRoot = $ProtectProjectId
    }
    $server = [pscustomobject]@{
        Ok           = $false
        Detail       = 'skipped'
        MuxMaster    = ''
        SftpCount    = -1
        ServerMain   = @()
        ListenPorts  = @()
    }
    if (-not $SkipServer -and (Get-Command SshX -ErrorAction SilentlyContinue)) {
        try {
            $cmd = @'
set +e
echo LISTEN_BEGIN
ss -ltnp 2>/dev/null | grep -E "127\.0\.0\.1:20[0-9]{3}" || true
echo LISTEN_END
echo MUX_BEGIN
ls -1 "$HOME/.cache/laptop-exec"/cm-* 2>/dev/null | head -20 || true
for s in "$HOME/.cache/laptop-exec"/cm-*; do
  [ -S "$s" ] || continue
  ssh -O check -o ControlPath="$s" -o ControlMaster=no -o BatchMode=yes -o ConnectTimeout=2 x 2>&1 | head -1 | sed "s|^|MUX:$s:|"
done
echo MUX_END
echo SFTP_BEGIN
ps -u "$USER" -o pid= -o cmd= 2>/dev/null | grep -c "[s]ftp" || echo 0
echo SFTP_END
echo SM_BEGIN
ps -u "$USER" -o pid=,etime=,cmd= 2>/dev/null | grep "server-main.js" | grep -v grep || true
echo SM_END
'@ -replace "`r", ''
            $raw = SshX $cmd
            $server.Ok = $true
            $server.Detail = 'ok'
            $server.ListenPorts = @([regex]::Matches([string]$raw, '127\.0\.0\.1:(20\d{3})') | ForEach-Object { [int]$_.Groups[1].Value } | Select-Object -Unique)
            if ($raw -match '(?m)^(\d+)\s*$' -and $raw -match 'SFTP_BEGIN') {
                $m = [regex]::Match([string]$raw, '(?s)SFTP_BEGIN\s*(\d+)')
                if ($m.Success) { $server.SftpCount = [int]$m.Groups[1].Value }
            }
            $server.MuxMaster = (($raw -split "`n" | Where-Object { $_ -match '^MUX:' -and $_ -match 'Master running' }) -join ';')
            $server.ServerMain = @(($raw -split "`n" | Where-Object { $_ -match 'server-main\.js' } | Select-Object -First 5))
        } catch {
            $server.Detail = $_.Exception.Message
        }
    }
    $report = [pscustomobject]@{
        PortBase        = $base
        CurrentPid      = [int]$PID
        CurrentTunnelPid = $currentTunnelPid
        ProtectRootName = $protectRoot
        ProtectRemotePath = ($ProtectRemotePath + '').Trim()
        Markers         = $markers
        Tunnels         = $tunnels
        OrphanTunnelPids = @($orphanPids | Select-Object -Unique)
        Siblings        = $siblingEntries
        SoftTargetCount = @($orphanPids | Select-Object -Unique).Count
        SiblingCount    = @($siblingEntries).Count
        Server          = $server
    }
    Write-GitModeLog ("HYGIENE_SCAN orphans={0} siblings={1} tunnels={2} server_ok={3}" -f $report.SoftTargetCount, $report.SiblingCount, @($tunnels).Count, $server.Ok) 'INFO'
    return $report
}

function Invoke-ConnectHygieneClean {
    param(
        [Parameter(Mandatory)][ValidateSet('Soft','Sibling')][string]$Mode,
        [Parameter(Mandatory)]$Report,
        [string]$ProtectRemotePath = '',
        [string]$ProtectProjectId = ''
    )
    $protectRoot = ($Report.ProtectRootName + '').Trim()
    if (-not $protectRoot) {
        if ($ProtectRemotePath) {
            $protectRoot = [System.IO.Path]::GetFileName(($ProtectRemotePath.TrimEnd('/','\')))
        } elseif ($ProtectProjectId) {
            $protectRoot = $ProtectProjectId
        }
    }
    $result = [pscustomobject]@{
        Mode            = $Mode
        OrphansKilled   = 0
        SiblingTunnels  = 0
        SiblingConnects = 0
        CursorWindows   = 0
        ServerReaper    = ''
        MuxCleaned      = 0
    }
    if ($Mode -eq 'Soft') {
        Write-GitModeLog 'HYGIENE_SOFT begin' 'INFO'
        $base = [int]$Report.PortBase
        for ($slot = 0; $slot -lt 10; $slot++) {
            $port = $base + $slot
            $before = @(Get-LocalTunnelSshPids -TargetPort $port)
            $null = Remove-LocalOrphanTunnel -TargetPort $port -CurrentBgTunnel $script:SessionBgTunnel -ProtectedProcessIds @([int]$PID, [int]$Report.CurrentTunnelPid)
            $after = @(Get-LocalTunnelSshPids -TargetPort $port)
            $result.OrphansKilled += [Math]::Max(0, $before.Count - $after.Count)
        }
        if (Get-Command SshX -ErrorAction SilentlyContinue) {
            try {
                $reaperOut = SshX 'command -v cursor-server-reaper >/dev/null && cursor-server-reaper --apply --user "$USER" 2>&1 | tail -5 || echo REAPER_SKIP'
                $result.ServerReaper = ([string]$reaperOut).Trim()
                $reaperOne = ($result.ServerReaper -replace '\s+', ' ')
                if ($reaperOne.Length -gt 200) { $reaperOne = $reaperOne.Substring(0, 200) }
                Write-GitModeLog ("HYGIENE_SOFT reaper={0}" -f $reaperOne) 'INFO'
            } catch {
                $result.ServerReaper = 'fail-open'
            }
            try {
                $muxOut = SshX @'
set +e
n=0
for s in "$HOME/.cache/laptop-exec"/cm-*; do
  [ -e "$s" ] || continue
  if ! ssh -O check -o ControlPath="$s" -o ControlMaster=no -o BatchMode=yes -o ConnectTimeout=2 x >/dev/null 2>&1; then
    rm -f "$s" 2>/dev/null && n=$((n+1))
  fi
done
echo MUX_DEAD_REMOVED=$n
'@
                if ($muxOut -match 'MUX_DEAD_REMOVED=(\d+)') { $result.MuxCleaned = [int]$Matches[1] }
            } catch { }
        }
        Write-GitModeLog ("HYGIENE_SOFT done orphans_killed={0} mux_dead={1}" -f $result.OrphansKilled, $result.MuxCleaned) 'INFO'
        return $result
    }

    # Sibling mode
    Write-GitModeLog 'HYGIENE_SIBLING begin' 'INFO'
    $seenUi = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($sib in @($Report.Siblings)) {
        $tPid = [int]$sib.TunnelPid
        $uiPid = [int]$sib.ConnectUiPid
        $port = [int]$sib.Port
        if ($tPid -gt 0 -and $tPid -ne [int]$Report.CurrentTunnelPid) {
            Write-GitModeLog ("HYGIENE_SIBLING_STOP tunnel pid={0} port={1}" -f $tPid, $port) 'INFO'
            Stop-TunnelProcessWithExitLog -ProcessId $tPid -Reason 'hygiene_sibling'
            $result.SiblingTunnels++
        }
        if ($uiPid -gt 0 -and $uiPid -ne [int]$PID -and -not $seenUi.Contains($uiPid)) {
            [void]$seenUi.Add($uiPid)
            try {
                Stop-Process -Id $uiPid -Force -ErrorAction Stop
                Write-GitModeLog ("HYGIENE_SIBLING_STOP connect_ui pid={0}" -f $uiPid) 'INFO'
                $result.SiblingConnects++
            } catch {
                Write-GitModeLog ("HYGIENE_SIBLING_STOP connect_ui_fail pid={0} err={1}" -f $uiPid, $_.Exception.Message) 'WARN'
            }
        }
        $root = ''
        if ($sib.RemotePath) {
            $root = [System.IO.Path]::GetFileName(($sib.RemotePath.TrimEnd('/','\')))
        } elseif ($sib.ProjectId) {
            $root = [string]$sib.ProjectId
        }
        if ($root -and (Get-Command Close-CursorProjectWindows -ErrorAction SilentlyContinue)) {
            if ($protectRoot -and ($root -ieq $protectRoot)) {
                Write-GitModeLog ("HYGIENE_SIBLING_CURSOR_SKIP root={0} reason=protect_current" -f $root) 'WARN'
            } else {
                $n = Close-CursorProjectWindows -ProjectRootName $root -ProtectRootName $protectRoot
                $result.CursorWindows += [int]$n
                Write-GitModeLog ("HYGIENE_SIBLING_CURSOR_WINDOW root={0} closed={1}" -f $root, $n) 'INFO'
            }
        } elseif (-not $root) {
            Write-GitModeLog 'HYGIENE_SIBLING_CURSOR_SKIP reason=unknown_project' 'WARN'
        }
        try {
            if ($sib.Slot -ge 0) { Clear-ConnectSessionSlotMarker -Slot ([int]$sib.Slot) }
        } catch { }
    }
    Write-GitModeLog ("HYGIENE_SIBLING done tunnels={0} connects={1} cursor_windows={2}" -f $result.SiblingTunnels, $result.SiblingConnects, $result.CursorWindows) 'INFO'
    return $result
}

function Show-ConnectHygieneInteractive {
    param(
        [string]$UidStr = '',
        [string]$ProtectRemotePath = '',
        [string]$ProtectProjectId = '',
        [string]$Alias = 'claude-server'
    )
    $report = Get-ConnectHygieneReport -UidStr $UidStr -ProtectRemotePath $ProtectRemotePath -ProtectProjectId $ProtectProjectId
    Write-Host ''
    Write-Host '    Hygiene scan' -ForegroundColor Cyan
    Write-Host ("    Orphan tunnels : {0}" -f $report.SoftTargetCount) -ForegroundColor DarkGray
    Write-Host ("    Sibling Connect: {0}" -f $report.SiblingCount) -ForegroundColor DarkGray
    foreach ($t in @($report.Tunnels)) {
        Write-Host ("      [{0}] port={1} tunnel={2} ui={3} project={4}" -f $t.Class, $t.Port, $t.TunnelPid, $t.ConnectUiPid, $(if ($t.ProjectId) { $t.ProjectId } else { '?' })) -ForegroundColor DarkGray
    }
    if ($report.Server.Ok) {
        Write-Host ("    Server mux/sftp : sftp={0} listens={1}" -f $report.Server.SftpCount, (@($report.Server.ListenPorts) -join ',')) -ForegroundColor DarkGray
    } else {
        Write-Host ("    Server scan    : {0}" -f $report.Server.Detail) -ForegroundColor DarkGray
    }
    Write-Host ''
    if ($report.SoftTargetCount -le 0 -and $report.SiblingCount -le 0) {
        Write-Host '    Nothing to clean.' -ForegroundColor Green
        Write-Host ''
        return
    }
    $ans = ''
    try { $ans = (Read-Host '    Soft-clean orphans/idle? [Y/N]').Trim().ToLowerInvariant() } catch { $ans = 'n' }
    if ($ans -ne 'y' -and $ans -ne 'yes') {
        Write-Host '    Cancelled.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }
    $soft = Invoke-ConnectHygieneClean -Mode Soft -Report $report -ProtectRemotePath $ProtectRemotePath -ProtectProjectId $ProtectProjectId
    Write-Host ("    Soft done: orphans_removed~{0} mux_dead={1}" -f $soft.OrphansKilled, $soft.MuxCleaned) -ForegroundColor Green
    $report2 = Get-ConnectHygieneReport -UidStr $UidStr -ProtectRemotePath $ProtectRemotePath -ProtectProjectId $ProtectProjectId -SkipServer
    if ($report2.SiblingCount -le 0) {
        Write-Host ''
        return
    }
    Write-Host ''
    Write-Host ("    {0} sibling Connect session(s) still live." -f $report2.SiblingCount) -ForegroundColor Yellow
    Write-Host '    This closes their tunnel, Connect window, and that project Cursor window only.' -ForegroundColor DarkGray
    $ans2 = ''
    try { $ans2 = (Read-Host '    Close sibling sessions? [Y/N]').Trim().ToLowerInvariant() } catch { $ans2 = 'n' }
    if ($ans2 -ne 'y' -and $ans2 -ne 'yes') {
        Write-Host '    Left siblings running.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }
    $sib = Invoke-ConnectHygieneClean -Mode Sibling -Report $report2 -ProtectRemotePath $ProtectRemotePath -ProtectProjectId $ProtectProjectId
    Write-Host ("    Sibling clean: tunnels={0} connects={1} cursor_windows={2}" -f $sib.SiblingTunnels, $sib.SiblingConnects, $sib.CursorWindows) -ForegroundColor Green
    Write-Host ''
}

function Get-StoredLaptopHostKeyFingerprint {
    if ($script:LaptopHostKeyFp) { return [string]$script:LaptopHostKeyFp }
    if (-not $Cfg -or -not (Test-Path $Cfg)) { return '' }
    $line = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^LAPTOP_HOSTKEY_FP=' } | Select-Object -Last 1
    if ($line -match '^LAPTOP_HOSTKEY_FP=(.+)$') {
        $script:LaptopHostKeyFp = $Matches[1].Trim()
        return [string]$script:LaptopHostKeyFp
    }
    return ''
}

function Save-LaptopHostKeyFingerprint {
    param([Parameter(Mandatory)][string]$Fingerprint)
    $fp = ($Fingerprint -replace '\s', '').Trim()
    if (-not $fp) { return }
    $script:LaptopHostKeyFp = $fp
    if (-not $Cfg) { return }
    $lines = @()
    if (Test-Path $Cfg) {
        $lines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^LAPTOP_HOSTKEY_FP=' })
    }
    $lines += "LAPTOP_HOSTKEY_FP=$fp"
    Set-Content -Path $Cfg -Value $lines -Encoding ASCII
    Write-GitModeLog "HOSTKEY_FP saved fp=$fp" 'INFO'
}

function Get-ForeignTunnelPortSet {
    # Unary comma on both returns: an empty HashSet enumerates to zero pipeline
    # objects on a bare `return`, which collapses to $null at the call site and
    # crashes Test-CachedForeignTunnelPort's `.Contains()` (same pitfall already
    # called out on Get-ServerOpenTunnelPorts above).
    if ($script:ForeignTunnelPortSet) { return ,$script:ForeignTunnelPortSet }
    $set = New-Object "System.Collections.Generic.HashSet[int]"
    if ($Cfg -and (Test-Path $Cfg)) {
        $line = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match "^FOREIGN_TUNNEL_PORTS=" } | Select-Object -Last 1
        if ($line -match "^FOREIGN_TUNNEL_PORTS=(.*)$") {
            foreach ($part in @($Matches[1] -split "[,\s]+")) {
                $p = 0
                if ([int]::TryParse($part.Trim(), [ref]$p) -and $p -gt 0) { [void]$set.Add($p) }
            }
        }
    }
    $script:ForeignTunnelPortSet = $set
    return ,$set
}

function Save-ForeignTunnelPortSet {
    if (-not $Cfg) { return }
    $set = Get-ForeignTunnelPortSet
    $csv = (@($set | Sort-Object) -join ",")
    $lines = @()
    if (Test-Path $Cfg) {
        $lines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^FOREIGN_TUNNEL_PORTS=" })
    }
    if ($csv) { $lines += "FOREIGN_TUNNEL_PORTS=$csv" }
    Set-Content -Path $Cfg -Value $lines -Encoding ASCII
}

function Test-TunnelPortInOwnUidBlock {
    param([Parameter(Mandatory)][int]$TargetPort)
    $uid = $null
    if ($script:ServerUidStr) { $uid = [string]$script:ServerUidStr }
    if (-not $uid) { return $false }
    $base = [int](Get-TunnelPortUserBase -UidStr $uid)
    if ($base -le 20000) { return $false }
    return ($TargetPort -ge $base -and $TargetPort -le ($base + 9))
}

function Remove-ForeignTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    if (-not $TargetPort) { return }
    $set = Get-ForeignTunnelPortSet
    $removed = $set.Remove($TargetPort)
    if ($script:ForeignTunnelPortSeenAt -and $script:ForeignTunnelPortSeenAt.ContainsKey($TargetPort)) {
        $script:ForeignTunnelPortSeenAt.Remove($TargetPort)
    }
    if ($script:ForeignTunnelPortPermanent -and $script:ForeignTunnelPortPermanent.Contains($TargetPort)) {
        [void]$script:ForeignTunnelPortPermanent.Remove($TargetPort)
    }
    if ($removed) {
        Save-ForeignTunnelPortSet
        Write-GitModeLog "FOREIGN_PORT forget port=$TargetPort" 'INFO'
    }
}

function Add-ForeignTunnelPort {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [switch]$Permanent
    )
    if (-not $TargetPort) { return }
    $set = Get-ForeignTunnelPortSet
    $added = $set.Add($TargetPort)
    if (-not $script:ForeignTunnelPortSeenAt) { $script:ForeignTunnelPortSeenAt = @{} }
    if (-not $script:ForeignTunnelPortPermanent) { $script:ForeignTunnelPortPermanent = New-Object "System.Collections.Generic.HashSet[int]" }
    if ($Permanent) { [void]$script:ForeignTunnelPortPermanent.Add($TargetPort) }
    $script:ForeignTunnelPortSeenAt[$TargetPort] = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($added) {
        Save-ForeignTunnelPortSet
        Write-GitModeLog ("FOREIGN_PORT remembered port={0} permanent={1}" -f $TargetPort, [int][bool]$Permanent) "INFO"
    }
}

function Test-CachedForeignTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    $set = Get-ForeignTunnelPortSet
    if (-not $set.Contains($TargetPort)) { return $false }
    $permanent = $false
    if ($script:ForeignTunnelPortPermanent -and $script:ForeignTunnelPortPermanent.Contains($TargetPort)) { $permanent = $true }
    $inOwn = $false
    if (Get-Command Test-TunnelPortInOwnUidBlock -ErrorAction SilentlyContinue) {
        $inOwn = [bool](Test-TunnelPortInOwnUidBlock -TargetPort $TargetPort)
    }
    if ($inOwn -and -not $permanent) {
        if (-not $script:ForeignTunnelPortSeenAt) { $script:ForeignTunnelPortSeenAt = @{} }
        $ttl = 300
        if ($script:ForeignTunnelPortTtlSec) { $ttl = [int]$script:ForeignTunnelPortTtlSec }
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $seen = 0
        if ($script:ForeignTunnelPortSeenAt.ContainsKey($TargetPort)) { $seen = [long]$script:ForeignTunnelPortSeenAt[$TargetPort] }
        if ($seen -le 0 -or ($now - $seen) -ge $ttl) {
            Remove-ForeignTunnelPort -TargetPort $TargetPort
            Write-GitModeLog "FOREIGN_PORT forget port=$TargetPort reason=own_block_ttl ttl=$ttl" 'INFO'
            return $false
        }
    }
    # Outside own block (or permanent hostkey pin): trust cache.
    Write-GitModeLog "ACQUIRE_SKIP: foreign_peer cached port=$TargetPort" "DEBUG"
    return $true
}

# Short-TTL (disk-persisted) memory of ports we JUST proved safe-to-reclaim and
# cleared via Clear-ServerStaleTunnelForward. Unlike FOREIGN_TUNNEL_PORTS (permanent
# until manually removed), this expires in a few seconds - it only exists to spare a
# second connect.ps1 launch (e.g. opening a 2nd/3rd project window moments apart) from
# repeating the full tcp/banner/hostkey/auth-owned chain on a port whose safety was
# already established a moment ago by THIS laptop. Never skips the live TCP probe in
# Get-ServerOpenTunnelPorts - only skips re-verifying ownership of an already-proven port.
$script:ClearedTunnelPortTtlSec = 8
$script:ForeignTunnelPortTtlSec = 300

function Get-ClearedTunnelPortMap {
    if ($script:ClearedTunnelPortMap) { return $script:ClearedTunnelPortMap }
    $map = @{}
    if ($Cfg -and (Test-Path $Cfg)) {
        $line = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match "^CLEARED_TUNNEL_PORTS=" } | Select-Object -Last 1
        if ($line -match "^CLEARED_TUNNEL_PORTS=(.*)$") {
            $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            foreach ($part in @($Matches[1] -split ",")) {
                if ($part -match '^(\d+):(\d+)$') {
                    $p = [int]$Matches[1]; $t = [long]$Matches[2]
                    if (($nowEpoch - $t) -lt $script:ClearedTunnelPortTtlSec) { $map[$p] = $t }
                }
            }
        }
    }
    $script:ClearedTunnelPortMap = $map
    return $map
}

function Save-ClearedTunnelPortMap {
    if (-not $Cfg) { return }
    $map = Get-ClearedTunnelPortMap
    $csv = (@($map.Keys | ForEach-Object { "{0}:{1}" -f $_, $map[$_] }) -join ",")
    $lines = @()
    if (Test-Path $Cfg) {
        $lines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^CLEARED_TUNNEL_PORTS=" })
    }
    if ($csv) { $lines += "CLEARED_TUNNEL_PORTS=$csv" }
    Set-Content -Path $Cfg -Value $lines -Encoding ASCII
}

function Add-ClearedTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    if (-not $TargetPort) { return }
    $map = Get-ClearedTunnelPortMap
    $map[$TargetPort] = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Save-ClearedTunnelPortMap
    Write-GitModeLog "CLEARED_PORT remembered port=$TargetPort ttl=$($script:ClearedTunnelPortTtlSec)s" "DEBUG"
}

function Test-RecentlyClearedTunnelPort {
    param([Parameter(Mandatory)][int]$TargetPort)
    $map = Get-ClearedTunnelPortMap
    if (-not $map.ContainsKey($TargetPort)) { return $false }
    $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (($nowEpoch - [long]$map[$TargetPort]) -ge $script:ClearedTunnelPortTtlSec) { return $false }
    Write-GitModeLog "ACQUIRE_SKIP: recently_cleared cached port=$TargetPort" "DEBUG"
    return $true
}

function Get-TunnelHostKeyFingerprint {
    param([Parameter(Mandatory)][int]$TargetPort)
    if (-not $TargetPort) { return '' }
    if (-not $script:TunnelHostKeyFpByPort) { $script:TunnelHostKeyFpByPort = @{} }
    $key = [string]$TargetPort
    if ($script:TunnelHostKeyFpByPort.ContainsKey($key)) {
        return [string]$script:TunnelHostKeyFpByPort[$key]
    }
    # ssh-keyscan on the server loopback reverse port; fingerprint is stable per laptop sshd.
    $out = (SshX "timeout 4 ssh-keyscan -p $TargetPort -T 3 -t ed25519,rsa,ecdsa 127.0.0.1 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print `$2}' | head -1") -join ''
    $fp = (($out -replace "`r", '') -replace '\s', '').Trim()
    if ($fp -and $fp -notmatch '^(SHA256:|MD5:)') { $fp = '' }
    if ($fp) {
        Write-GitModeLog "HOSTKEY_FP scan port=$TargetPort fp=$fp" 'DEBUG'
    }
    $script:TunnelHostKeyFpByPort[$key] = $fp
    return $fp
}

function Test-TunnelHostKeyMismatch {
    param([Parameter(Mandatory)][int]$TargetPort)
    $stored = Get-StoredLaptopHostKeyFingerprint
    if (-not $stored) { return $false }
    $fp = Get-TunnelHostKeyFingerprint -TargetPort $TargetPort
    if (-not $fp) { return $false }
    if ($fp -ne $stored) {
        Write-GitModeLog "ACQUIRE_SKIP: hostkey_mismatch port=$TargetPort got=$fp want=$stored" 'INFO'
        if (Get-Command Add-ForeignTunnelPort -ErrorAction SilentlyContinue) { Add-ForeignTunnelPort -TargetPort $TargetPort -Permanent }
        return $true
    }
    return $false
}

function Clear-TunnelAuthOwnedCache {
    param([int]$TargetPort = 0)
    if (-not $script:TunnelAuthOwnedCache) { return }
    if ($TargetPort -gt 0) { $script:TunnelAuthOwnedCache.Remove($TargetPort) | Out-Null }
    else { $script:TunnelAuthOwnedCache.Clear() }
}

function Test-TunnelPortAuthOwned {
    param([Parameter(Mandatory)][int]$TargetPort)
    # True only when server can pubkey-auth to THIS laptop user via the candidate reverse port.
    # Distinguishes our sticky forward from another Windows peer (same OpenSSH_for_Windows banner).
    if (-not $LaptopUser) { return $false }
    if (-not $TargetPort) { return $false }
    # Memoize for a few seconds: Acquire-TunnelPort's Pass 2 can reach this port both
    # directly and indirectly (via Test-TunnelPortIsForeignPeer) within the same
    # evaluation - without this, the real ssh auth attempt (up to ~6s) ran twice.
    if (-not $script:TunnelAuthOwnedCache) { $script:TunnelAuthOwnedCache = @{} }
    $cached = $script:TunnelAuthOwnedCache[$TargetPort]
    if ($cached -and ((Get-Date) - $cached.At).TotalMilliseconds -lt 5000) {
        Write-GitModeLog "TUNNEL_OWNERSHIP port=$TargetPort owned=$($cached.Owned) cache_hit=1" 'TRACE'
        return $cached.Owned
    }
    $kh = '$HOME/.ssh/known_hosts_claude_acquire'
    $lu = ($LaptopUser -replace "'", "'\''")
    $out = (SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null; timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=3 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $TargetPort ${lu}@127.0.0.1 powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command exit 2>&1") -join "`n"
    $ok = ($LASTEXITCODE -eq 0)
    $script:TunnelAuthOwnedCache[$TargetPort] = @{ Owned = $ok; At = (Get-Date) }
    if (-not $ok) {
        $tail = @($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        Write-GitModeLog "TUNNEL_OWNERSHIP port=$TargetPort owned=0 detail=$tail" 'DEBUG'
    } else {
        Write-GitModeLog "TUNNEL_OWNERSHIP port=$TargetPort owned=1" 'DEBUG'
    }
    return $ok
}

function Test-TunnelPortIsForeignPeer {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    # Server listens with a Windows SSH banner, but this PC has no live ssh -R for the port,
    # and claude_laptop cannot auth as LAPTOP_USER => another user's reverse tunnel (do not kill).
        if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
        if (Test-CachedForeignTunnelPort -TargetPort $TargetPort) { return $true }
    }
    if (Get-Command Test-RecentlyClearedTunnelPort -ErrorAction SilentlyContinue) {
        if (Test-RecentlyClearedTunnelPort -TargetPort $TargetPort) { return $false }
    }
$tcpOpen = $false
    # Perf (H12): Test-TunnelHostKeyMismatch below is about to call
    # Get-TunnelHostKeyFingerprint (its own ssh-keyscan SSH round trip) whenever a
    # stored laptop host-key fingerprint exists and this port hasn't been scanned yet.
    # Prefetch it in the SAME call as the tcp-open re-check via
    # Test-TunnelPortTcpOpenAndScanHostKey - Test-TunnelHostKeyMismatch then just hits
    # the (now warm) per-port cache and issues zero extra SSH calls. When there is no
    # stored fingerprint yet, Test-TunnelHostKeyMismatch never scans at all (returns
    # early) - so behavior there is unchanged and we skip the combined probe too.
    $hkAlreadyCached = [bool]($script:TunnelHostKeyFpByPort -and $script:TunnelHostKeyFpByPort.ContainsKey([string]$TargetPort))
    $hkStored = ''
    if (-not $hkAlreadyCached -and (Get-Command Get-StoredLaptopHostKeyFingerprint -ErrorAction SilentlyContinue)) {
        $hkStored = Get-StoredLaptopHostKeyFingerprint
    }
    try {
        if ($hkStored -and -not $hkAlreadyCached) {
            $tcpOpen = [bool](Test-TunnelPortTcpOpenAndScanHostKey -TargetPort $TargetPort)
        } else {
            $tcpOpen = [bool](Test-TunnelPortTcpOpen -TargetPort $TargetPort)
        }
    } catch { $tcpOpen = $false }
        if (-not $tcpOpen) {
            # Closed port cannot be a live foreign peer - skip expensive banner/hostkey SSH.
            return $false
        }
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner -TargetPort $TargetPort
        # Absolute pin: different sshd host key than our laptop => never claim/kill.
        if (Test-TunnelHostKeyMismatch -TargetPort $TargetPort) {
            Write-GitModeLog "ACQUIRE_SKIP: foreign_peer hostkey port=$TargetPort" 'INFO'
            return $true
        }
        $localPids = @(Get-LocalTunnelSshPids -TargetPort $TargetPort)
        $protected = @($ProtectedProcessIds)
        if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $protected += [int]$CurrentBgTunnel.Id }
        if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) { $protected += [int]$script:SessionBgTunnel.Id }
        $oursLocal = $false
        foreach ($processId in $localPids) {
            if ($protected -contains $processId) { $oursLocal = $true; break }
        }
        if ($oursLocal) { return $false }
        if ($localPids.Count -gt 0) {
            return $false
        }
        if (Test-TunnelPortAuthOwned -TargetPort $TargetPort) {
            Write-GitModeLog "TUNNEL_OWNERSHIP port=$TargetPort sticky_ours=1 (no local -R)" 'DEBUG'
            return $false
        }
        $inOwnBlock = $false
        if (Get-Command Test-TunnelPortInOwnUidBlock -ErrorAction SilentlyContinue) {
            $inOwnBlock = [bool](Test-TunnelPortInOwnUidBlock -TargetPort $TargetPort)
        }
        # Own UID block: tcpOpen + no local -R + auth not owned => INDETERMINATE (not foreign).
        # Avoid permanent false-foreign pins (e.g. 20028) that shrink the 10-port block.
        if ($inOwnBlock -and ($tcpOpen -or (Test-TunnelBannerIsWindows -Banner $banner))) {
            Write-GitModeLog "FOREIGN_INDETERMINATE port=$TargetPort banner=$banner tcp=$tcpOpen auth_owned=0" 'INFO'
            return $false
        }
        if ($tcpOpen -or (Test-TunnelBannerIsWindows -Banner $banner)) {
            if (Get-Command Add-ForeignTunnelPort -ErrorAction SilentlyContinue) {
                Add-ForeignTunnelPort -TargetPort $TargetPort
            }
            Write-GitModeLog "ACQUIRE_SKIP: foreign_peer port=$TargetPort banner=$banner tcp=$tcpOpen" 'INFO'
            return $true
        }
        return $false
}

function Get-LocalTunnelPortPidMap {
    # One CIM scan for all ssh -R forwards (avoids ~500ms Get-CimInstance per port).
    $map = @{}
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $null -ne (Get-LocalTunnelSshReversePortFromCommandLine -CommandLine $_.CommandLine) } |
        ForEach-Object {
            $p = Get-LocalTunnelSshReversePortFromCommandLine -CommandLine $_.CommandLine
            if ($null -eq $p) { return }
            if (-not $map.ContainsKey($p)) { $map[$p] = New-Object System.Collections.Generic.List[int] }
            $map[$p].Add([int]$_.ProcessId)
        }
    return $map
}

function Import-PrefetchedOpenTunnelPorts {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$UidStr
    )
    if (-not $UidStr) { return $null }
    $openSet = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($line in @($Lines)) {
        if ($line -match 'OPEN:(\d+)') { [void]$openSet.Add([int]$Matches[1]) }
    }
    $portBase = Get-TunnelPortUserBase -UidStr $UidStr
    $probed = New-Object "System.Collections.Generic.List[int]"
    0..9 | ForEach-Object {
        $p = $portBase + $_
        if ($p -gt 20000 -and $p -le 65535) { [void]$probed.Add($p) }
    }
    if ($probed.Count -eq 0) { return $null }
    foreach ($p in $probed) {
        Set-TunnelTcpState -Port $p -Open $openSet.Contains($p)
    }
    $script:PrefetchedOpenTunnelPorts = @{
        Probed = @($probed)
        Open   = $openSet
    }
    Write-GitModeLog ("PREFETCH_OPEN_PORTS open={0} probed={1}" -f (($openSet | Sort-Object) -join ','), $probed.Count) 'DEBUG'
    return $script:PrefetchedOpenTunnelPorts
}

function Get-PrefetchedOpenTunnelPortSet {
    param([Parameter(Mandatory)][int[]]$Ports)
    if (-not $script:PrefetchedOpenTunnelPorts) { return $null }
    $batch = $script:PrefetchedOpenTunnelPorts
    $probedSet = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($p in @($batch.Probed)) { [void]$probedSet.Add([int]$p) }
    foreach ($p in @($Ports)) {
        if (-not $probedSet.Contains([int]$p)) {
            Write-GitModeLog "PREFETCH_OPEN_PORTS miss port=$p - need live batch" 'DEBUG'
            return $null
        }
    }
    $openSet = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($p in @($Ports)) {
        if ($batch.Open.Contains([int]$p)) { [void]$openSet.Add([int]$p) }
    }
    $script:PrefetchedOpenTunnelPorts = $null
    Write-GitModeLog ("ACQUIRE_BATCH open_ports={0} probed={1} source=prefetch" -f (($openSet | Sort-Object) -join ','), @($Ports).Count) 'DEBUG'
    return ,$openSet
}

function Test-WarmLocalConfForeignSkip {
    # Skip server LU/OS/PORT probe when laptop conf already reflects this user's sticky slot.
    if (-not $Cfg -or -not (Test-Path -LiteralPath $Cfg)) { return $false }
    $mine = if ($script:LaptopUser) { [string]$script:LaptopUser } elseif ($env:USERNAME) { [string]$env:USERNAME } else { [string]$env:USER }
    if ([string]::IsNullOrWhiteSpace($mine)) { return $false }
    $lu = ''; $port = ''; $slot = ''
    foreach ($ln in @(Get-Content -LiteralPath $Cfg -ErrorAction SilentlyContinue)) {
        if ($ln -match '^LAPTOP_USER=(.+)$') { $lu = $Matches[1].Trim() }
        elseif ($ln -match '^(PORT|TUNNEL_PORT)=(2\d{4})$') { $port = $Matches[2] }
        elseif ($ln -match '^TUNNEL_SLOT=(\d+)$') { $slot = $Matches[1] }
    }
    if (-not $lu -or ($lu -ne $mine)) { return $false }
    if (-not $port -or -not ($slot -match '^\d+$')) { return $false }
    $portInt = 0
    if (-not [int]::TryParse($port, [ref]$portInt)) { return $false }
    if ($portInt -le 20000 -or $portInt -gt 65535) { return $false }
    $slotInt = [int]$slot
    if ($slotInt -lt 0 -or $slotInt -gt 9) { return $false }
    return $true
}

function Get-ServerOpenTunnelPorts {
    param([int[]]$Ports = @())
    $set = New-Object "System.Collections.Generic.HashSet[int]"
    if ($null -eq $Ports -or @($Ports).Count -eq 0) {
        Write-GitModeLog 'ACQUIRE_BATCH open_ports= probed=0' 'DEBUG'
        # Unary comma: empty HashSet must not enumerate to $null (PS pipeline unwrap).
        return ,$set
    }
    $list = (@($Ports) | Select-Object -Unique) -join ' '
    # One SSH, parallel short probes - closed ports fail in ~250ms, not 1s serial each.
    $script = @"
for p in $list; do
  ( timeout 0.25 bash -c "exec 3<>/dev/tcp/127.0.0.1/`$p" 2>/dev/null && echo OPEN:`$p ) &
done
wait
"@
    $script = (($script -replace "`r`n", "`n") -replace "`r", "`n")
    $out = (SshX $script 2>$null) -join "`n"
    foreach ($line in @($out -split "`n")) {
        if ($line -match 'OPEN:(\d+)') { [void]$set.Add([int]$Matches[1]) }
    }
    # Seed the short-TTL tcp-state cache for EVERY probed port (open and closed). The push-conf
    # safety gate and the ENSURE_TUNNEL stale-forward check re-examine the chosen port within a few
    # seconds; reusing this verdict removes two fresh ~1.4s one-shot ssh probes per connect.
    foreach ($p in @($Ports)) {
        if ([int]$p -gt 0) { Set-TunnelTcpState -Port ([int]$p) -Open ([bool]$set.Contains([int]$p)) }
    }
    Write-GitModeLog ("ACQUIRE_BATCH open_ports={0} probed={1}" -f (($set | Sort-Object) -join ','), @($Ports).Count) 'DEBUG'
    # Unary comma prevents PS from enumerating HashSet into ints/$null on assignment.
    return ,$set
}
function Get-TunnelPortUserBase {
    param([Parameter(Mandatory)][string]$UidStr)
    # Non-overlapping 10-port block per user, instead of the old `20000 + uid + slot(0-9)`
    # scheme. That old formula overlapped by up to 6 of 10 ports between any two users with
    # adjacent UIDs - true for this whole team, since Ubuntu assigns sequential UIDs from 1000
    # (verified: 1000-1018 for all 19 accounts here). That overlap was the entire reason
    # Acquire-TunnelPort needs its expensive foreign-peer/hostkey-mismatch/auth-owned
    # verification chain: a port could genuinely be ambiguous between two different users'
    # ranges. With disjoint ranges, a port outside your own block is unambiguously someone
    # else's (fast, permanent FOREIGN_TUNNEL_PORTS cache hit, no more flip-flopping), and a
    # port inside your own block that isn't yours locally is unambiguously your own stale
    # zombie. The existing verification chain is left fully in place as defense-in-depth -
    # this only fixes the formula that made it so frequently necessary.
    # Assumes Ubuntu's standard first-normal-UID=1000; clamps instead of going negative for
    # any (unexpected) system-range UID below that.
    $uid = 0
    if (-not [int]::TryParse($UidStr, [ref]$uid)) { return 20000 }
    $offset = $uid - 1000
    if ($offset -lt 0) { $offset = 0 }
    return 20000 + ($offset * 10)
}

function Test-LocalPortFree {
    param([Parameter(Mandatory)][int]$PortNum)
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, $PortNum)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) { try { $listener.Stop() } catch {} }
    }
}

function Get-SocksProxyPort {
    # Fixed Cursor SOCKS local forward (independent of UI TunnelSlot).
    return 19080
}

function Get-HttpProxyPort {
    # Fixed Cursor HTTP local forward for settings.json / undici.
    return 19180
}

function Get-CursorSocksFrontPort {
    if ($script:CursorSocksFrontPort) { return [int]$script:CursorSocksFrontPort }
    return (Get-SocksProxyPort)
}

function Get-CursorHttpFrontPort {
    if ($script:CursorHttpFrontPort) { return [int]$script:CursorHttpFrontPort }
    return (Get-HttpProxyPort)
}

function Test-LocalPortOpen {
    param([Parameter(Mandatory)][int]$PortNum, [int]$TimeoutMs = 400)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect([System.Net.IPAddress]::Loopback, $PortNum, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if (-not $ok) { return $false }
        try { $client.EndConnect($iar) } catch { return $false }
        return [bool]$client.Connected
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}

function Get-CursorProxyOwnerPath {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect'
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
    }
    return (Join-Path $dir 'cursor-proxy-owner.json')
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        return ($null -ne $p -and -not $p.HasExited)
    } catch { return $false }
}

function Get-CursorProxyOwnerInfo {
    $path = Get-CursorProxyOwnerPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null }
}

function Test-IsCursorProxyOwner {
    $info = Get-CursorProxyOwnerInfo
    if (-not $info) { return $false }
    $pidOwn = 0
    try { $pidOwn = [int]$info.pid } catch { $pidOwn = 0 }
    if (-not (Test-ProcessAlive -ProcessId $pidOwn)) { return $false }
    return ($pidOwn -eq $PID)
}

function Test-CanClaimCursorProxyOwner {
    # Read-only mirror of Claim success without writing owner.json.
    # ForeignLiveOwner := alive + pid != self + Connect-shaped cmdline -> CanBindL false.
    $info = Get-CursorProxyOwnerInfo
    if (-not $info) { return $true }
    $pidOwn = 0
    try { $pidOwn = [int]$info.pid } catch { return $true }
    if ($pidOwn -le 0) { return $true }
    if ($pidOwn -eq $PID) { return $true }
    if (-not (Test-ProcessAlive -ProcessId $pidOwn)) { return $true }
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$pidOwn" -ErrorAction Stop
        $cmd = [string]$cim.CommandLine
        if (Get-Command Test-ProcessCommandIsConnectUi -ErrorAction SilentlyContinue) {
            if (-not (Test-ProcessCommandIsConnectUi -CommandLine $cmd)) {
                return $true # PID reuse by non-Connect -> Claim would adopt
            }
        }
    } catch {
        # Unreadable cmdline: treat as foreign-live (safe: skip kill)
        return $false
    }
    return $false
}

function Test-ProxyReseedShouldKill {
    # Single chokepoint: ReseedEffective = ReseedRaw AND CanClaim (CanBindL).
    # Under Gap (ReseedRaw + NOT CanBindL) return $false so callers keep -R.
    param(
        [Parameter(Mandatory)][int]$TunnelPid,
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = ''
    )
    if (-not (Test-TunnelNeedsProxyReseed -TunnelPid $TunnelPid -Alias $Alias -SshCfgPath $SshCfgPath)) {
        return $false
    }
    if (-not (Test-CanClaimCursorProxyOwner)) {
        Write-GitModeLog "ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind pid=$TunnelPid port=$Port" 'WARN'
        return $false
    }
    return $true
}

function Claim-CursorProxyOwner {
    param([switch]$Force)
    $path = Get-CursorProxyOwnerPath
    $info = Get-CursorProxyOwnerInfo
    if ($info -and -not $Force) {
        $pidOwn = 0
        try { $pidOwn = [int]$info.pid } catch { $pidOwn = 0 }
        if ($pidOwn -eq $PID) {
            $script:CursorProxyOwner = $true
            return $true
        }
        if (Test-ProcessAlive -ProcessId $pidOwn) {
            $adoptNonConnect = $false
            try {
                $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$pidOwn" -ErrorAction Stop
                $cmd = [string]$cim.CommandLine
                if ((Get-Command Test-ProcessCommandIsConnectUi -ErrorAction SilentlyContinue) -and
                    -not (Test-ProcessCommandIsConnectUi -CommandLine $cmd)) {
                    $adoptNonConnect = $true
                }
            } catch {
                $adoptNonConnect = $false
            }
            if ($adoptNonConnect) {
                Write-GitModeLog ("CURSOR_PROXY_OWNER: adopt stale_non_connect pid={0} self={1}" -f $pidOwn, $PID) 'INFO'
            } else {
                $script:CursorProxyOwner = $false
                Write-GitModeLog ("CURSOR_PROXY_OWNER: skip live_owner pid={0} self={1}" -f $pidOwn, $PID) 'INFO'
                return $false
            }
        } else {
            Write-GitModeLog ("CURSOR_PROXY_OWNER: adopt stale pid={0} self={1}" -f $pidOwn, $PID) 'INFO'
        }
    }
    $payload = [ordered]@{
        pid         = $PID
        slot        = $(if ($null -ne $script:TunnelSlot) { [int]$script:TunnelSlot } else { -1 })
        socks       = (Get-SocksProxyPort)
        http        = (Get-HttpProxyPort)
        started_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    try {
        ($payload | ConvertTo-Json -Compress) | Set-Content -LiteralPath $path -Encoding UTF8 -Force
        $script:CursorProxyOwner = $true
        Write-GitModeLog ("CURSOR_PROXY_OWNER: claimed pid={0} socks={1}" -f $PID, $payload.socks) 'INFO'
        return $true
    } catch {
        $script:CursorProxyOwner = $false
        Write-GitModeLog ("CURSOR_PROXY_OWNER: claim_fail $($_.Exception.Message)") 'WARN'
        return $false
    }
}

function Release-CursorProxyOwner {
    param([string]$Reason = '')
    if (-not (Test-IsCursorProxyOwner)) { return }
    $path = Get-CursorProxyOwnerPath
    try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch {}
    $script:CursorProxyOwner = $false
    $script:ProxyOwnerServiceDeadSince = $null
    if ($Reason -eq 'service_dead') {
        # S2 token must appear literally (Win/Mac parity).
        Write-GitModeLog "CURSOR_PROXY_OWNER: released reason=service_dead pid=$PID" 'INFO'
    } elseif ($Reason) {
        Write-GitModeLog "CURSOR_PROXY_OWNER: released reason=$Reason pid=$PID" 'INFO'
    } else {
        Write-GitModeLog "CURSOR_PROXY_OWNER: released pid=$PID" 'INFO'
    }
}

function Get-CursorProxyHealthNow {
    # Injectable clock for owner/service-dead timer tests (CursorProxyHealthNow).
    if ($null -ne $script:CursorProxyHealthNow) {
        try { return [datetime]$script:CursorProxyHealthNow } catch {}
    }
    return (Get-Date)
}

function Get-NoProcZombieNow {
    # Injectable clock for no_proc keep-alive age gate tests (NoProcZombieNow).
    if ($null -ne $script:NoProcZombieNow) {
        try { return [datetime]$script:NoProcZombieNow } catch {}
    }
    return (Get-Date)
}

function Test-NoProcShouldKeepAlive {
    # Returns $true when no_proc keep-alive should continue (age < NO_PROC_ZOMBIE_SEC,
    # or age>=threshold with auth+Windows banner). $false => caller zombie_drop+Release.
    $nowZ = Get-NoProcZombieNow
    if (-not $script:NoProcKeepAliveSince) { $script:NoProcKeepAliveSince = $nowZ }
    $zombieAge = 0.0
    try { $zombieAge = ($nowZ - [datetime]$script:NoProcKeepAliveSince).TotalSeconds } catch { $zombieAge = 0.0 }
    $zombieSec = 120
    if ($script:NoProcZombieSec) { try { $zombieSec = [int]$script:NoProcZombieSec } catch { $zombieSec = 120 } }
    if ($zombieSec -lt 1) { $zombieSec = 120 }
    if ($zombieAge -lt $zombieSec) { return $true }
    $authOwned = $false
    try { $authOwned = [bool](Test-TunnelPortAuthOwned -TargetPort $Port) } catch { $authOwned = $false }
    $bannerOk = $false
    try {
        $zb = Get-TunnelBanner
        if ($zb) { $bannerOk = [bool](Test-TunnelBannerIsWindows -Banner $zb) }
    } catch { $bannerOk = $false }
    return ($authOwned -and $bannerOk)
}

function Test-CursorProxyBackendsUp {
    $backSocks = 0
    $backHttp = 0
    if ($script:SocksProxyPort) { try { $backSocks = [int]$script:SocksProxyPort } catch { $backSocks = 0 } }
    if ($script:HttpProxyPort) { try { $backHttp = [int]$script:HttpProxyPort } catch { $backHttp = 0 } }
    if ($backSocks -le 0 -and (Get-Command Get-SocksProxyPort -ErrorAction SilentlyContinue)) {
        try { $backSocks = [int](Get-SocksProxyPort) } catch { $backSocks = 0 }
    }
    if ($backHttp -le 0 -and (Get-Command Get-HttpProxyPort -ErrorAction SilentlyContinue)) {
        try { $backHttp = [int](Get-HttpProxyPort) } catch { $backHttp = 0 }
    }
    if ($backSocks -le 0 -or $backHttp -le 0) { return $false }
    return ((Test-LocalPortOpen -PortNum $backSocks) -and (Test-LocalPortOpen -PortNum $backHttp))
}

function Update-CursorProxyOwnerServiceHealth {
    # OwnerServiceDead := IsOwner AND NOT BackendsUp AND XrayExpected
    #   AND age(ProxyOwnerServiceDeadSince) >= SERVICE_DEAD_SEC (60)
    # XrayExpected := SessionEverHadProxyLegs (not bare intentional xray_closed).
    # Called from Complete AND Sync so zombie owners release without Ensure churn.
    if (-not (Test-IsCursorProxyOwner)) { return }
    $xrayExpected = [bool]$script:SessionEverHadProxyLegs
    if (-not $xrayExpected) {
        $script:ProxyOwnerServiceDeadSince = $null
        return
    }
    $backendsUp = $false
    try { $backendsUp = [bool](Test-CursorProxyBackendsUp) } catch { $backendsUp = $false }
    $now = Get-CursorProxyHealthNow
    if ($backendsUp) {
        $script:ProxyOwnerServiceDeadSince = $null
        return
    }
    if (-not $script:ProxyOwnerServiceDeadSince) {
        $script:ProxyOwnerServiceDeadSince = $now
        return
    }
    $deadSec = 60
    if ($script:ServiceDeadSec) { try { $deadSec = [int]$script:ServiceDeadSec } catch { $deadSec = 60 } }
    if ($deadSec -lt 1) { $deadSec = 60 }
    $age = 0.0
    try { $age = ($now - [datetime]$script:ProxyOwnerServiceDeadSince).TotalSeconds } catch { $age = 0.0 }
    if ($age -ge $deadSec) {
        Write-GitModeLog ("CURSOR_PROXY_OWNER: service_dead age_sec={0} threshold={1}" -f [int]$age, $deadSec) 'WARN'
        Release-CursorProxyOwner -Reason 'service_dead'
    }
}



function Get-CursorProxyMode {
    # Classify how Cursor should reach the internet for this Connect session:
    #   sidecar       = sticky 18999/18998 front listening AND backend -L up
    #   xray          = tunnel -L backends up (no healthy front)
    #   server_direct = last resort (no healthy local proxy; remote uses server NIC)
    $frontSocks = Get-CursorSocksFrontPort
    $frontHttp = Get-CursorHttpFrontPort
    $frontUp = $false
    if ($frontSocks -gt 0 -and $frontHttp -gt 0) {
        $frontUp = (Test-LocalPortOpen -PortNum $frontSocks) -and (Test-LocalPortOpen -PortNum $frontHttp)
    }
    $backSocks = 0
    $backHttp = 0
    if ($script:SocksProxyPort) { $backSocks = [int]$script:SocksProxyPort }
    elseif (Get-Command Get-SocksProxyPort -ErrorAction SilentlyContinue) { $backSocks = [int](Get-SocksProxyPort) }
    if ($script:HttpProxyPort) { $backHttp = [int]$script:HttpProxyPort }
    elseif (Get-Command Get-HttpProxyPort -ErrorAction SilentlyContinue) { $backHttp = [int](Get-HttpProxyPort) }
    $backUp = $false
    if ($backSocks -gt 0 -and $backHttp -gt 0) {
        $backUp = (Test-LocalPortOpen -PortNum $backSocks) -and (Test-LocalPortOpen -PortNum $backHttp)
    }
    if ($frontUp -and $backUp) { return 'sidecar' }
    if ($backUp) { return 'xray' }
    return 'server_direct'
}

function Complete-CursorProxyAfterTunnel {
    # Must run on EVERY successful Ensure-SessionTunnel path (spawn AND reuse).
    # Reuse used to return early without touching the sticky sidecar - Cursor then kept
    # settings http.proxy=127.0.0.1:18998 while the front door was dead -> agent error
    # "Failed to establish a socket connection to proxies: PROXY 127.0.0.1:18998".
    # Last resort when all proxies fail: clear dead 18998 so laptop chat can recover
    # while remote Machine settings use server NIC (server_direct).
    #
    # Fast path (live Preparing-tunnel 14929ms / 15022ms, 2026-07-28): when THIS tunnel
    # has no -L proxy legs (xray closed), Ensure-CursorProxySidecar starts sticky fronts
    # against dead backends and flaps ~10s. NEVER "adopt" orphan 19080/19180 listeners via
    # Get-SocksProxyPort defaults — that defeated skip on reuse when SessionTunnelProxyLegs
    # was unset (Bugbot 2026-07-28). Only session-claimed legs may start the sidecar.
    # Owner/service coupling: tick health even on early skip (xray_closed must not service_dead).
    if (Get-Command Update-CursorProxyOwnerServiceHealth -ErrorAction SilentlyContinue) {
        if (Test-IsCursorProxyOwner) {
            try { Update-CursorProxyOwnerServiceHealth } catch {}
        }
    }
    $sessionSocks = 0
    $sessionHttp = 0
    if ($script:SocksProxyPort) { try { $sessionSocks = [int]$script:SocksProxyPort } catch { $sessionSocks = 0 } }
    if ($script:HttpProxyPort) { try { $sessionHttp = [int]$script:HttpProxyPort } catch { $sessionHttp = 0 } }
    # Explicit false (xray_closed / reuse no -L) wins even if stale SocksProxyPort remains.
    if ($script:SessionTunnelProxyLegs -eq $false) {
        Write-GitModeLog 'Complete-CursorProxyAfterTunnel skip_sidecar reason=no_tunnel_proxy_legs' 'INFO'
        $frontHttp = Get-CursorHttpFrontPort
        if ($frontHttp -gt 0 -and (Test-LocalPortOpen -PortNum $frontHttp)) {
            if (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                try { [void](Clear-CursorProxySettingsSidecar) } catch {}
            }
        }
        Write-GitModeLog 'PROXY_FALLBACK mode=server_direct reason=no_tunnel_proxy_legs' 'INFO'
        Write-GitModeLog 'CURSOR_PROXY_MODE mode=server_direct' 'INFO'
        return
    }
    $sessionHasLegs = ($script:SessionTunnelProxyLegs -eq $true) -or ($sessionSocks -gt 0) -or ($sessionHttp -gt 0)
    if (-not $sessionHasLegs) {
        Write-GitModeLog 'Complete-CursorProxyAfterTunnel skip_sidecar reason=no_tunnel_proxy_legs' 'INFO'
        $frontHttp = Get-CursorHttpFrontPort
        if ($frontHttp -gt 0 -and (Test-LocalPortOpen -PortNum $frontHttp)) {
            if (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                try { [void](Clear-CursorProxySettingsSidecar) } catch {}
            }
        }
        Write-GitModeLog 'PROXY_FALLBACK mode=server_direct reason=no_tunnel_proxy_legs' 'INFO'
        Write-GitModeLog 'CURSOR_PROXY_MODE mode=server_direct' 'INFO'
        return
    }
    if (Get-Command Ensure-CursorProxySidecar -ErrorAction SilentlyContinue) {
        try { [void](Ensure-CursorProxySidecar) } catch {
            if (Get-Command Start-CursorProxySidecar -ErrorAction SilentlyContinue) {
                try { [void](Start-CursorProxySidecar) } catch {}
            }
        }
    } elseif (Get-Command Start-CursorProxySidecar -ErrorAction SilentlyContinue) {
        try { [void](Start-CursorProxySidecar) } catch {}
    }
    if (Get-Command Test-ProxyHealth -ErrorAction SilentlyContinue) {
        try { [void](Test-ProxyHealth) } catch {}
    }
    $frontHttp = Get-CursorHttpFrontPort
    $frontListening = $false
    if ($frontHttp -gt 0) {
        $frontListening = [bool](Test-LocalPortOpen -PortNum $frontHttp)
    }
    if ($script:LastProxyHealthOk -eq $false) {
        if (-not $frontListening) {
            # Prefer sidecar CLEAR (safe with windows open). Full CLEAR only if allowed.
            $cleared = $false
            if (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                try { $cleared = [bool](Clear-CursorProxySettingsSidecar) } catch { $cleared = $false }
            }
            if (-not $cleared -and (Get-Command Clear-CursorProxySettings -ErrorAction SilentlyContinue)) {
                $may = $true
                if (Get-Command Test-MayClearCursorProxySettings -ErrorAction SilentlyContinue) {
                    try { $may = [bool](Test-MayClearCursorProxySettings -AllowClear) } catch { $may = $false }
                }
                if ($may) {
                    try { [void](Clear-CursorProxySettings) } catch {}
                } else {
                    Write-GitModeLog 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open_or_non_owner action=reload_for_server_direct' 'WARN'
                }
            }
            Write-GitModeLog 'PROXY_FALLBACK mode=server_direct reason=proxy_health_fail_front_down' 'WARN'
        } else {
            # Front still listening but egress health failed (e.g. austria dead).
            if (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                try { [void](Clear-CursorProxySettingsSidecar) } catch {}
            }
            Write-GitModeLog 'PROXY_FALLBACK mode=server_direct reason=proxy_health_fail' 'WARN'
        }
    } elseif (Get-Command Repair-CursorProxySettingsToSidecar -ErrorAction SilentlyContinue) {
        # Health OK through 18998 - keep sticky settings aligned.
        try { [void](Repair-CursorProxySettingsToSidecar) } catch {}
    }
    $mode = 'server_direct'
    try { $mode = Get-CursorProxyMode } catch { $mode = 'server_direct' }
    Write-GitModeLog ("CURSOR_PROXY_MODE mode={0}" -f $mode) 'INFO'
    if (Get-Command Update-CursorProxyOwnerServiceHealth -ErrorAction SilentlyContinue) {
        if (Test-IsCursorProxyOwner) {
            try { Update-CursorProxyOwnerServiceHealth } catch {}
        }
    }
}

function Test-ProxyHealth {
    # H10_proxy_health_timeout: default was 10s and, worse, was NEVER actually applied to the
    # request (WebClient has no .Timeout property) - a dead backend leg made DownloadString hang
    # until the OS/TCP layer detected the reset (~8.6s observed live). Switched to HttpWebRequest,
    # which does honor .Timeout, and lowered the default to 3s (api.ipify.org is a tiny response;
    # a genuinely-working proxy answers in well under 1s, so 3s is still a generous margin).
    param([int]$HttpPort = 0, [int]$SocksPort = 0, [int]$TimeoutSec = 2)
    if ($HttpPort -le 0) { $HttpPort = Get-CursorHttpFrontPort }
    if ($SocksPort -le 0) { $SocksPort = Get-CursorSocksFrontPort }
    if ($HttpPort -le 0) {
        Write-GitModeLog 'PROXY_HEALTH ok=0 reason=no_http_port' 'WARN'
        return $false
    }
    if (-not (Test-LocalPortOpen -PortNum $HttpPort)) {
        Write-GitModeLog ("PROXY_HEALTH socks={0} http={1} ok=0 reason=http_not_listening" -f $SocksPort, $HttpPort) 'WARN'
        return $false
    }
    # Fast-fail when the sidecar backend legs are down: the front door (18998) can be up while
    # its upstream backend (-L 19080/19180) is dead, in which case the HTTPS probe below would
    # forward into a dead backend and hang until the full timeout (~4.5s observed live). A cheap
    # bounded local port check on the backend short-circuits that stall straight to server_direct.
    if (Get-Command Test-CursorProxyBackendOpen -ErrorAction SilentlyContinue) {
        if (-not (Test-CursorProxyBackendOpen)) {
            Write-GitModeLog ("PROXY_HEALTH socks={0} http={1} ok=0 reason=backend_not_listening" -f $SocksPort, $HttpPort) 'WARN'
            $script:LastProxyHealthOk = $false
            return $false
        }
    }
    $ip = ''
    try {
        $req = [System.Net.HttpWebRequest]::Create('https://api.ipify.org')
        $req.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:$HttpPort")
        $req.UserAgent = 'claude-connect-proxy-health'
        $timeoutMs = [Math]::Max(500, $TimeoutSec * 1000)
        $req.Timeout = $timeoutMs
        $req.ReadWriteTimeout = $timeoutMs
        $resp = $req.GetResponse()
        try {
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $ip = $reader.ReadToEnd().Trim()
            $reader.Close()
        } finally {
            $resp.Close()
        }
    } catch {
        Write-GitModeLog ("PROXY_HEALTH socks={0} http={1} ok=0 err={2}" -f $SocksPort, $HttpPort, $_.Exception.Message) 'WARN'
        $script:LastProxyHealthOk = $false
        return $false
    }
    if (-not $ip) {
        Write-GitModeLog ("PROXY_HEALTH socks={0} http={1} ok=0 reason=empty_ip" -f $SocksPort, $HttpPort) 'WARN'
        $script:LastProxyHealthOk = $false
        return $false
    }
    Write-GitModeLog ("PROXY_HEALTH socks={0} http={1} ok=1 ip={2}" -f $SocksPort, $HttpPort, $ip) 'INFO'
    $script:LastProxyHealthOk = $true
    $script:LastProxyHealthIp = $ip
    return $true
}


# Server-side SOCKS5 listener of the xray proxy (systemd service `xray`, /etc/systemd/system/
# xray.service), 127.0.0.1-only. Verified to egress via a distinct IP (Austria VLESS exit),
# NOT the shared office IP that the laptop and server both otherwise share - a plain ssh -D
# to the server itself would have exposed that same shared/flagged IP and fixed nothing.
# We forward server-side xray SOCKS via -L instead of -D.
$script:XrayServerSocksPort = 10808
$script:XrayServerHttpPort = 10809
$script:CursorSocksFrontPort = 18999
$script:CursorHttpFrontPort = 18998
$script:TunnelWaitBackoffSec = 2
$script:TunnelWaitFailStreak = 0
$script:CursorProxyOwner = $null
$script:LastProxyHealthOk = $false
$script:LastProxyHealthIp = ''
# Cache for the remote xray SOCKS/HTTP probe. Each probe opens a FRESH one-shot ssh (no
# ControlMaster on Windows) and, thanks to the Win32-OpenSSH ConnectTimeout bug, can burn the
# full ~7s budget. It is probed at least twice per connect (boot Ensure-Tunnel + session-loop
# Test-TunnelNeedsProxyReseed), and every new connect.bat is a FRESH process, so without a cache
# the ~7s "Server setup" probe is paid on every single launch. The cache is disk-backed so the
# (usually 'closed') verdict survives across processes; a reconnect after the TTL re-probes, so a
# genuinely changed xray state still recovers. One TTL governs both the in-process reuse and the
# cross-process disk reuse.
$script:XrayProbeCache = @{}
$script:XrayProbeCacheTtlSec = 1800
$script:XrayProbeDiskLoaded = $false

function Get-XrayProbeCachePath {
    $dir = if ($script:CfgDir) { $script:CfgDir } elseif ($CfgDir) { $CfgDir } else { Join-Path $env:USERPROFILE '.config\claude-connect' }
    return (Join-Path $dir 'xray-probe-cache.json')
}

function Import-XrayProbeDiskCache {
    # Lazy, once-per-process: hydrate the in-memory cache from disk so a fresh connect.bat can skip
    # the ~7s boot probe. Entries older than the TTL are dropped on load.
    if ($script:XrayProbeDiskLoaded) { return }
    $script:XrayProbeDiskLoaded = $true
    try {
        $p = Get-XrayProbeCachePath
        if (-not (Test-Path -LiteralPath $p)) { return }
        $raw = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
        # A JSON *object* deserializes to a single PSCustomObject (no array-unroll quirk here).
        $obj = $raw | ConvertFrom-Json
        if (-not $obj) { return }
        foreach ($prop in $obj.PSObject.Properties) {
            $val = $prop.Value
            $t = $null
            try { $t = [datetime]::Parse([string]$val.Time, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch { $t = $null }
            if ($null -eq $t) { continue }
            if (((Get-Date) - $t).TotalSeconds -ge $script:XrayProbeCacheTtlSec) { continue }
            if (-not $script:XrayProbeCache.ContainsKey($prop.Name)) {
                $script:XrayProbeCache[$prop.Name] = @{ Result = [bool]$val.Result; Time = $t }
            }
        }
    } catch {}
}

function Save-XrayProbeDiskCache {
    try {
        $p = Get-XrayProbeCachePath
        $dir = Split-Path -Parent $p
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $flat = @{}
        foreach ($k in @($script:XrayProbeCache.Keys)) {
            $e = $script:XrayProbeCache[$k]
            $flat[$k] = @{ Result = [bool]$e.Result; Time = ([datetime]$e.Time).ToString('o') }
        }
        ($flat | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $p -Encoding UTF8
    } catch {}
}

function Test-RemoteXraySocksOpen {
    # Probe 127.0.0.1:10808 ON THE DESTINATION SERVER (not laptop). Sepidz has no xray -
    # must return false so we never wire -L or write http.proxy to a dead endpoint.
    #
    # Single ssh attempt, single clear timeout budget - no attempt+retry stacking (bug 3/4
    # fix, 2026-07-24). The previous design ran attempt1 capped at WaitForExit(5000) and,
    # only on timeout, a full SECOND ssh process capped at WaitForExit(6000) - worst case
    # 5000+6000=11000ms, which is *worse* than the ~8000ms budget it was meant to protect,
    # while attempt1 alone still stalled routinely against a target that wasn't actually
    # unreachable (cold SSH under boot-time connection bursts). Research:
    #   - Win32-OpenSSH ConnectTimeout has a long-standing non-blocking-poll bug
    #     (PowerShell/Win32-OpenSSH#1352, OpenSSH bug 2918): the client waits the ENTIRE
    #     ConnectTimeout duration rather than only capping genuinely-slow connects - i.e.
    #     "ConnectTimeout=N" is a "wait up to Ns" budget that is frequently fully consumed,
    #     not a tight fast-fail guarantee.
    #   - OpenSSH sshd_config MaxStartups (default 10:30:100): once the number of pending
    #     *unauthenticated* connections crosses the low watermark, sshd starts randomly
    #     dropping/delaying a percentage of new connection attempts, and the probability
    #     rises linearly up to the high watermark - worse under boot-time SSH bursts from
    #     many concurrent client sessions. This is genuine cold-start slowness, not a dead
    #     target, so a single attempt needs a real window to succeed rather than being
    #     retried from scratch.
    # Net effect: one attempt with ConnectTimeout=6 (ssh-level) + WaitForExit(7000) (process
    # backstop, giving the ssh-level timeout room to fire on its own first) keeps worst-case
    # wall-clock meaningfully under the original ~8000ms budget while still giving a
    # genuinely slow-but-eventually-successful connection a fair single window to complete.
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = '',
        [int]$RemotePort = 0,
        [switch]$ForceProbe
    )
    if ($RemotePort -le 0) { $RemotePort = [int]$script:XrayServerSocksPort }
    Import-XrayProbeDiskCache
    $cacheKey = "$Alias`:$RemotePort"
    if (-not $ForceProbe -and $script:XrayProbeCache -and $script:XrayProbeCache.ContainsKey($cacheKey)) {
        $entry = $script:XrayProbeCache[$cacheKey]
        if (((Get-Date) - $entry.Time).TotalSeconds -lt $script:XrayProbeCacheTtlSec) {
            Write-GitModeLog "ENSURE_TUNNEL remote_xray_probe=cache_hit port=$RemotePort result=$($entry.Result)" 'DEBUG'
            return $entry.Result
        }
    }
    $result = $false
    # A timeout/error is INCONCLUSIVE (Win32-OpenSSH ConnectTimeout can spuriously burn the full
    # budget against a target that is actually up). Never persist an inconclusive verdict as a
    # definitive "closed" - that poisoned the cache for the whole TTL and permanently dropped the
    # proxy leg on a healthy xray. Only cache a real OPEN/CLOSED reply from the remote.
    $conclusive = $true
    $argList = New-Object System.Collections.Generic.List[string]
    if ($SshCfgPath) { [void]$argList.Add('-F'); [void]$argList.Add($SshCfgPath) }
    foreach ($a in @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=6', '-o', 'ServerAliveInterval=2', '-o', 'ServerAliveCountMax=2')) {
        [void]$argList.Add($a)
    }
    [void]$argList.Add($Alias)
    [void]$argList.Add("timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$RemotePort' 2>/dev/null && echo OPEN || echo CLOSED")
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $proc = $null
    try {
        $proc = Start-Process -FilePath 'ssh' -ArgumentList $argList.ToArray() -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $proc.WaitForExit(7000)) {
            try { $proc.Kill() } catch {}
            Write-GitModeLog "ENSURE_TUNNEL remote_xray_probe=timeout port=$RemotePort skipping_proxy_leg" 'WARN'
            $result = $false
            $conclusive = $false
        } else {
            $out = ''
            try { $out = [System.IO.File]::ReadAllText($stdoutPath).Trim() } catch { $out = '' }
            if ($out -eq 'OPEN' -or $out -eq 'CLOSED') { $result = ($out -eq 'OPEN') }
            else { $result = $false; $conclusive = $false }
        }
    } catch {
        $result = $false
        $conclusive = $false
    } finally {
        try { Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($conclusive -and $script:XrayProbeCache -ne $null) {
        $script:XrayProbeCache[$cacheKey] = @{ Result = $result; Time = (Get-Date) }
        Save-XrayProbeDiskCache
    }
    return $result
}

function Set-SocksProxyPortOnReuse {
    # Keep prior Socks/Http ports on failure so concurrent Launch cannot race into CLEAR.
    # Always set SessionTunnelProxyLegs so Complete-CursorProxyAfterTunnel never falls into
    # "unset flag + orphan listener" thrash on the common reuse path (Bugbot 2026-07-28).
    param(
        [Parameter(Mandatory)][int]$TunnelPid,
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = ''
    )
    $prevSocks = $script:SocksProxyPort
    $prevHttp = $script:HttpProxyPort
    $socksCandidate = Get-SocksProxyPort
    $httpCandidate = Get-HttpProxyPort
    $xrayPort = [int]$script:XrayServerSocksPort
    $xrayHttpPort = [int]$script:XrayServerHttpPort
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$TunnelPid" -ErrorAction Stop
        $cmd = [string]$cim.CommandLine
        $fwdPat = "-L\s+127\.0\.0\.1:${socksCandidate}:127\.0\.0\.1:${xrayPort}"
        $httpFwdPat = "-L\s+127\.0\.0\.1:${httpCandidate}:127\.0\.0\.1:${xrayHttpPort}"
        if ($cmd -notmatch $fwdPat -or $cmd -notmatch $httpFwdPat) {
            $script:SessionTunnelProxyLegs = $false
            return
        }
        if (-not (Test-LocalPortOpen -PortNum $socksCandidate)) {
            $script:SessionTunnelProxyLegs = $false
            return
        }
        if (-not (Test-LocalPortOpen -PortNum $httpCandidate)) {
            $script:SessionTunnelProxyLegs = $false
            return
        }
        if (-not (Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath)) {
            $script:SessionTunnelProxyLegs = $false
            return
        }
        if (-not (Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath -RemotePort $xrayHttpPort)) {
            $script:SessionTunnelProxyLegs = $false
            return
        }
        $script:SocksProxyPort = $socksCandidate
        $script:HttpProxyPort = $httpCandidate
        $script:SessionTunnelProxyLegs = $true
        Write-GitModeLog "ENSURE_TUNNEL reuse_proxy ok local=$socksCandidate remote=$xrayPort http_local=$httpCandidate http_remote=$xrayHttpPort" 'INFO'
    } catch {
        $script:SessionTunnelProxyLegs = $false
        if ($prevSocks) { $script:SocksProxyPort = $prevSocks }
        if ($prevHttp) { $script:HttpProxyPort = $prevHttp }
    }
}

function Get-TunnelProxyLegState {
    # Classify reverse-tunnel ssh cmdline for the xray proxy leg.
    # ok           = SOCKS + HTTP -L to server xray
    # missing_http = SOCKS -L without HTTP -L
    # legacy_D     = old ssh -D (office-IP egress) - must reseed
    # missing  = no -L / -D for our socks port - must reseed when xray is up
    # unknown  = process gone / unreadable
    param([Parameter(Mandatory)][int]$TunnelPid)
    $socksCandidate = Get-SocksProxyPort
    $xrayPort = [int]$script:XrayServerSocksPort
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$TunnelPid" -ErrorAction Stop
        $cmd = [string]$cim.CommandLine
        if (-not $cmd) { return 'unknown' }
        $httpCandidate = Get-HttpProxyPort
        $xrayHttpPort = [int]$script:XrayServerHttpPort
        $fwdPat = "-L\s+127\.0\.0\.1:${socksCandidate}:127\.0\.0\.1:${xrayPort}"
        $httpFwdPat = "-L\s+127\.0\.0\.1:${httpCandidate}:127\.0\.0\.1:${xrayHttpPort}"
        if ($cmd -match $fwdPat) {
            if ($cmd -match $httpFwdPat) { return 'ok' }
            return 'missing_http'
        }
        if ($cmd -match "-D\s+127\.0\.0\.1:${socksCandidate}\b") { return 'legacy_D' }
        return 'missing'
    } catch {
        return 'unknown'
    }
}


function Add-TunnelHttpProxyLeg {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$SshArgs,
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = ''
    )
    if (-not $script:SocksProxyPort) { return }
    $httpCandidate = Get-HttpProxyPort
    $xrayHttpPort = [int]$script:XrayServerHttpPort
    $httpXrayOk = Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath -RemotePort $xrayHttpPort
    if (-not $httpXrayOk) {
        # The first probe can spuriously time out (Win32-OpenSSH ConnectTimeout burns its full
        # budget even against a live target) - and the SOCKS leg on the SAME transport just
        # succeeded, so xray is almost certainly up. Retry once, bypassing the cache, so a single
        # transient timeout cannot permanently drop the HTTP proxy leg. A missing HTTP leg makes
        # Test-CursorProxyBackendOpen fail -> the sidecar CLEARS Cursor's proxy settings -> Cursor
        # egresses server_direct instead of through xray (the exact bug seen live 2026-07-25).
        $httpXrayOk = Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath -RemotePort $xrayHttpPort -ForceProbe
        if ($httpXrayOk) { Write-GitModeLog "ENSURE_TUNNEL remote_xray_http=open_on_retry port=$xrayHttpPort" 'INFO' }
    }
    if (-not $httpXrayOk) {
        Write-GitModeLog "ENSURE_TUNNEL remote_xray_http=closed port=$xrayHttpPort skipping_http_proxy_leg" 'INFO'
        return
    }
    if (-not (Test-LocalPortFree -PortNum $httpCandidate)) {
        Write-GitModeLog "ENSURE_TUNNEL http_port_busy port=$httpCandidate skipping_http_proxy_leg" 'WARN'
        return
    }
    [void]$SshArgs.Add('-L')
    [void]$SshArgs.Add("127.0.0.1:${httpCandidate}:127.0.0.1:$xrayHttpPort")
    $script:HttpProxyPort = $httpCandidate
    Write-GitModeLog "ENSURE_TUNNEL http_proxy_leg=-L local=$httpCandidate remote=$xrayHttpPort" 'INFO'
}
function Test-TunnelNeedsProxyReseed {
    # When server xray SOCKS is open, refuse to keep a tunnel without the -L proxy leg
    # (or with legacy -D). Sepidz / no xray: never reseed for proxy.
    # After proxy_adopt busy_healthy, this Connect may lack -L (another owns 19080);
    # do not kill/respawn while backends or sticky fronts still listen.
    param(
        [Parameter(Mandatory)][int]$TunnelPid,
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = ''
    )
    # Cheap local cmdline check FIRST: if the existing tunnel already has the proxy leg ('ok') or
    # the process is gone/unreadable ('unknown'), no reseed is needed regardless of xray state, so
    # we can skip the expensive remote xray probe (a fresh ~7s one-shot ssh) entirely. Only when the
    # leg is actually missing/legacy do we need to know whether xray is up to decide about adding it.
    $state = Get-TunnelProxyLegState -TunnelPid $TunnelPid
    if ($state -eq 'ok') { return $false }
    if ($state -eq 'unknown') { return $false }
    if (-not (Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath)) { return $false }
    if ($state -eq 'missing' -or $state -eq 'missing_http') {
        $socksCandidate = Get-SocksProxyPort
        $httpCandidate = Get-HttpProxyPort
        $backendsOk = (Test-LocalPortOpen -PortNum $socksCandidate) -and (Test-LocalPortOpen -PortNum $httpCandidate)
        $frontsOk = $false
        # Sticky-front adoption only makes sense for a FULL non-owner ('missing': no -L legs at all),
        # which legitimately rides another window's proxy. For 'missing_http' (this tunnel already
        # owns the SOCKS -L but lost the HTTP -L), a listening front whose HTTP backend (19180) is
        # actually DOWN is a FALSE positive - it is exactly what left every window on server_direct
        # (front up, http backend dead -> sidecar clears Cursor proxy). So for missing_http, only a
        # genuinely-listening HTTP backend may suppress the reseed; never a front alone.
        if (-not $backendsOk -and $state -eq 'missing') {
            $frontSocks = Get-CursorSocksFrontPort
            $frontHttp = Get-CursorHttpFrontPort
            if (Get-Command Test-CursorProxySidecarListening -ErrorAction SilentlyContinue) {
                $frontsOk = (Test-CursorProxySidecarListening -Port $frontSocks) -and (Test-CursorProxySidecarListening -Port $frontHttp)
            } else {
                $frontsOk = (Test-LocalPortOpen -PortNum $frontSocks) -and (Test-LocalPortOpen -PortNum $frontHttp)
            }
        }
        if ($backendsOk -or $frontsOk) {
            Write-GitModeLog "ENSURE_TUNNEL reseed_skip reason=proxy_adopted_elsewhere state=$state socks=$socksCandidate http=$httpCandidate" 'INFO'
            if (-not $script:SocksProxyPort) { $script:SocksProxyPort = $socksCandidate }
            if (-not $script:HttpProxyPort) { $script:HttpProxyPort = $httpCandidate }
            return $false
        }
    }
    Write-GitModeLog "ENSURE_TUNNEL reseed_needed reason=$state pid=$TunnelPid socks=$(Get-SocksProxyPort)" 'WARN'
    return $true
}


function Clear-LegacyDynamicSocksTunnels {
    # Free OUR socks port only when a legacy ssh -D still holds it.
    # Never mass-kill other slots/sessions (that drops unrelated Cursor Remote-SSH windows).
    param(
        [int]$ProtectPid = 0,
        [int]$SocksPort = 0
    )
    if ($SocksPort -le 0) { $SocksPort = Get-SocksProxyPort }
    $killed = 0
    $dPat = "-D\s+127\.0\.0\.1:${SocksPort}\b"
    try {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue)) {
            $procId = [int]$p.ProcessId
            if ($ProtectPid -gt 0 -and $procId -eq $ProtectPid) { continue }
            $cmd = [string]$p.CommandLine
            if ($cmd -notmatch '(^|\s)-N(\s|$)') { continue }
            if ($cmd -notmatch '-R(?:\s*=\s*|\s+)\d+:(?:localhost|127\.0\.0\.1):22\b') { continue }
            if ($cmd -notmatch $dPat) { continue }
            if ($cmd -match "-L\s+127\.0\.0\.1:${SocksPort}:") { continue }
            if ($cmd -notmatch '\bclaude-server(\s|$)') { continue }
            if ($cmd -match 'claude-server-sepidz') { continue }
            try {
                Stop-TunnelProcessWithExitLog -ProcessId $procId -Reason 'legacy_D_cleanup'
                $killed++
            } catch {}
        }
    } catch {}
    if ($killed -gt 0) {
        Write-GitModeLog "ENSURE_TUNNEL legacy_D_cleanup killed=$killed socks=$SocksPort" 'WARN'
    }
    return $killed
}



function Acquire-TunnelPort {
    param(
        [string]$UidStr,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    $portBase = Get-TunnelPortUserBase -UidStr $UidStr
    if (-not $UidStr) { return $false }

    # Already bound to a live session tunnel - do not rescan.
    if ($Port -and $script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $mine = @($ProtectedProcessIds)
        $mine += [int]$script:SessionBgTunnel.Id
        if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $mine += [int]$CurrentBgTunnel.Id }
        $localNow = @(Get-LocalTunnelSshPids -TargetPort $Port)
        foreach ($tunnelPid in $localNow) {
            if ($mine -contains [int]$tunnelPid) {
                Write-GitModeLog "ACQUIRE_KEEP: session_tunnel port=$Port pid=$tunnelPid" 'DEBUG'
                return $true
            }
        }
    }

    $preferred = ''
    if ($env:CLAUDE_CONNECT_UI_SLOT -match '^\d+$') { $preferred = $env:CLAUDE_CONNECT_UI_SLOT }
    if (-not $preferred -and $Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
    # Also honor sticky PORT from conf when present.
    $preferredPort = $null
    if ($Cfg -and (Test-Path $Cfg)) {
        $portLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(PORT|TUNNEL_PORT)=' } | Select-Object -Last 1
        if ($portLine -match '=(2\d{4})$') { $preferredPort = [int]$Matches[1] }
    }

    $preferredInt = $null
    if ($preferred -match '^\d+$') { $preferredInt = [int]$preferred }
    $trySlots = @()
    if ($null -ne $preferredInt -and $preferredInt -le 9) { $trySlots += $preferredInt }
    0..9 | ForEach-Object { if ($_ -ne $preferredInt) { $trySlots += $_ } }

    $candidates = @()
    foreach ($slot in $trySlots) {
        $candPort = $portBase + $slot
        # Guard: 20000 < PORT (20000 is reserved sentinel). UID 1000 base+slot0 = 20000.
        if ($candPort -gt 20000 -and $candPort -le 65535) { $candidates += @{ Slot = $slot; Port = $candPort } }
    }
    # Hybrid: UI_SLOT order already preferred in $trySlots. Only boost conf PORT when UI slot unset.
    if ($preferredPort -and -not ($preferred -match '^\d+$')) {
        $candidates = @($candidates | Sort-Object { if ($_.Port -eq $preferredPort) { 0 } else { 1 } }, { $_.Slot })
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $localMap = Get-LocalTunnelPortPidMap
    $protected = @($ProtectedProcessIds)
    if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $protected += [int]$CurrentBgTunnel.Id }
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) { $protected += [int]$script:SessionBgTunnel.Id }

    $probePorts = @()
    foreach ($c in $candidates) {
        $candPort = [int]$c.Port
        if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
            if (Test-CachedForeignTunnelPort -TargetPort $candPort) { continue }
        }
        $peerLive = $false
        if ($localMap.ContainsKey($candPort)) {
            foreach ($processId in @($localMap[$candPort])) {
                if ($protected -contains [int]$processId) { continue }
                $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($proc -and -not $proc.HasExited) { $peerLive = $true; break }
            }
        }
        if ($peerLive) {
            Write-GitModeLog "ACQUIRE_SKIP: peer_live port=$candPort slot=$($c.Slot)" 'DEBUG'
            continue
        }
        $probePorts += $candPort
    }

    if (@($probePorts).Count -eq 0) {
        Write-GitModeLog 'ACQUIRE_FAST no_probe_ports (all peer_live/foreign) - trying sticky reclaim' 'WARN'
        $openSet = New-Object "System.Collections.Generic.HashSet[int]"
        # Prefer sticky conf PORT / UI slot even if marked peer_live - may be our orphan.
        $stickyPort = $null
        if ($preferredPort) { $stickyPort = [int]$preferredPort }
        elseif ($null -ne $preferredInt) { $stickyPort = $portBase + [int]$preferredInt }
        if ($stickyPort) {
            $stickySlot = [int]$stickyPort - $portBase
            if ($stickySlot -ge 0 -and $stickySlot -le 9) {
                if (-not (Test-CachedForeignTunnelPort -TargetPort $stickyPort)) {
                    $protSticky = @($ProtectedProcessIds)
                    if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $protSticky += [int]$CurrentBgTunnel.Id }
                    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) { $protSticky += [int]$script:SessionBgTunnel.Id }
                    $sibSticky = @()
                    if (Get-Command Get-SiblingConnectTunnelPids -ErrorAction SilentlyContinue) {
                        $sibSticky = @(Get-SiblingConnectTunnelPids -TargetPort $stickyPort -ProtectedProcessIds $protSticky)
                    }
                    if ($sibSticky.Count -gt 0) {
                        # Hybrid: never steal sibling -R; keep shared or take another free slot below.
                        Write-GitModeLog ("ACQUIRE_SKIP: sibling_live port={0} pids={1}" -f $stickyPort, ($sibSticky -join ',')) 'INFO'
                        Write-GitModeLog ("ACQUIRE_FAST sticky_shared port={0} slot={1} ms={2}" -f $stickyPort, $stickySlot, $sw.ElapsedMilliseconds) 'INFO'
                    } else {
                        $script:TunnelSlot = $stickySlot
                        $script:Port = $stickyPort
                        $Port = $script:Port
                        # Classify/orphan first, then publish (I6).
                        $null = Remove-LocalOrphanTunnel -TargetPort $stickyPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds
                        Save-TunnelSlot
                        Push-ServerConnectConf
                        Write-GitModeLog ("ACQUIRE_FAST claim_sticky port={0} slot={1} ms={2}" -f $stickyPort, $stickySlot, $sw.ElapsedMilliseconds) 'INFO'
                        return $true
                    }
                }
            }
        }
        # Last resort: first non-foreign slot in range (even if peer_live map said busy).
        foreach ($c in $candidates) {
            $candPort = [int]$c.Port
            $slot = [int]$c.Slot
            if (Test-CachedForeignTunnelPort -TargetPort $candPort) { continue }
            $protBusy = @($ProtectedProcessIds)
            if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $protBusy += [int]$CurrentBgTunnel.Id }
            if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) { $protBusy += [int]$script:SessionBgTunnel.Id }
            $sibBusy = @()
            if (Get-Command Get-SiblingConnectTunnelPids -ErrorAction SilentlyContinue) {
                $sibBusy = @(Get-SiblingConnectTunnelPids -TargetPort $candPort -ProtectedProcessIds $protBusy)
            }
            if ($sibBusy.Count -gt 0) {
                Write-GitModeLog ("ACQUIRE_SKIP: sibling_live port={0} slot={1}" -f $candPort, $slot) 'DEBUG'
                continue
            }
            $script:TunnelSlot = $slot
            $script:Port = $candPort
            $Port = $script:Port
            $null = Remove-LocalOrphanTunnel -TargetPort $candPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds
            Save-TunnelSlot
            Push-ServerConnectConf
            Write-GitModeLog ("ACQUIRE_FAST claim_busy_fallback port={0} slot={1} ms={2}" -f $candPort, $slot, $sw.ElapsedMilliseconds) 'WARN'
            return $true
        }
        if ($portBase -le 20000) {
            $script:Port = 20001
            $Port = $script:Port
            $script:TunnelSlot = 1
        } else {
            $script:Port = $portBase
            $Port = $script:Port
            $script:TunnelSlot = 0
        }
        Write-GitModeLog ("ACQUIRE_FAST fail_empty_probe ms={0} port={1}" -f $sw.ElapsedMilliseconds, $script:Port) 'WARN'
        return $false
    }
    $openSet = $null
    if (Get-Command Get-PrefetchedOpenTunnelPortSet -ErrorAction SilentlyContinue) {
        $openSet = Get-PrefetchedOpenTunnelPortSet -Ports $probePorts
    }
    if ($null -eq $openSet) {
        $openSet = Get-ServerOpenTunnelPorts -Ports $probePorts
    }
    if ($null -eq $openSet) {
        $openSet = New-Object "System.Collections.Generic.HashSet[int]"
    } elseif ($openSet -isnot [System.Collections.Generic.HashSet[int]]) {
        $normalized = New-Object "System.Collections.Generic.HashSet[int]"
        foreach ($op in @($openSet)) {
            if ($null -ne $op -and "$op" -match '^\d+$') { [void]$normalized.Add([int]$op) }
        }
        $openSet = $normalized
    }
    Write-GitModeLog ("ACQUIRE_FAST prep_ms={0} candidates={1} probe={2} open={3}" -f $sw.ElapsedMilliseconds, $candidates.Count, $probePorts.Count, $openSet.Count) 'INFO'

    # Pass 1: claim first CLOSED port (truly free) - no banner/hostkey/foreign SSH.
    foreach ($c in $candidates) {
        $candPort = [int]$c.Port
        $slot = [int]$c.Slot
        if ($probePorts -notcontains $candPort) { continue }
        if ($openSet.Contains($candPort)) { continue }
        $script:TunnelSlot = $slot
        $script:Port = $candPort
        $Port = $script:Port
        Save-TunnelSlot
        Push-ServerConnectConf
        Write-GitModeLog ("ACQUIRE_FAST claim_free port={0} slot={1} ms={2}" -f $candPort, $slot, $sw.ElapsedMilliseconds) 'INFO'
        return $true
    }

    # Pass 2: TCP-open ports - only then do ownership/foreign checks (expensive).
    foreach ($c in $candidates) {
        $candPort = [int]$c.Port
        $slot = [int]$c.Slot
        if ($probePorts -notcontains $candPort) { continue }
        if (-not $openSet.Contains($candPort)) { continue }
        if (Test-TunnelPortIsForeignPeer -TargetPort $candPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) {
            continue
        }
        $script:Port = $candPort
        $Port = $script:Port
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
        if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) {
            Write-GitModeLog "ACQUIRE_STALE: foreign_banner port=$candPort banner=$banner" 'DEBUG'
            Clear-ServerStaleTunnelForward -TargetPort $candPort
            Clear-TunnelBannerCache
            $banner = Get-TunnelBanner
            if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) { continue }
            if (Test-TunnelPortIsForeignPeer -TargetPort $candPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) { continue }
        }
        if (-not $banner) {
            if (Test-TunnelPortAuthOwned -TargetPort $candPort) {
                Write-GitModeLog "ACQUIRE_STALE: sticky_ours port=$candPort reclaim" 'DEBUG'
                Clear-ServerStaleTunnelForward -TargetPort $candPort
                Clear-TunnelBannerCache
                $banner = Get-TunnelBanner
            } elseif (Test-TunnelPortIsForeignPeer -TargetPort $candPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) {
                continue
            } else {
                Write-GitModeLog "ACQUIRE_STALE: zombie port=$candPort tcp=open banner=(empty)" 'WARN'
                Clear-ServerStaleTunnelForward -TargetPort $candPort
                Clear-TunnelBannerCache
                $banner = Get-TunnelBanner
            }
            if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) { continue }
            if (Test-TunnelPortIsForeignPeer -TargetPort $candPort -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) { continue }
            if (-not $banner -and $openSet.Contains($candPort)) { continue }
        }
        if (-not $banner -or (Test-TunnelBannerIsWindows -Banner $banner)) {
            $localNow = @(Get-LocalTunnelSshPids -TargetPort $candPort)
            if ($banner -and $localNow.Count -eq 0 -and -not (Test-TunnelPortAuthOwned -TargetPort $candPort)) {
                Write-GitModeLog "ACQUIRE_SKIP: unauth_windows port=$candPort slot=$slot" 'INFO'
                continue
            }
            $script:TunnelSlot = $slot
            $script:Port = $candPort
            $Port = $script:Port
            Save-TunnelSlot
            Push-ServerConnectConf
            Write-GitModeLog ("ACQUIRE_FAST claim_reclaim port={0} slot={1} ms={2}" -f $candPort, $slot, $sw.ElapsedMilliseconds) 'INFO'
            return $true
        }
    }

    $script:Port = $portBase
    $Port = $script:Port
    $script:TunnelSlot = 0
    Write-GitModeLog ("ACQUIRE_FAST fail ms={0} fallback_port={1}" -f $sw.ElapsedMilliseconds, $script:Port) 'WARN'
    return $false
}
function Test-TunnelUp {
    param([int]$Retries = 0)
    if (-not $Port) { return $false }
    # Session-fresh spawn trust (2026-07-25): Wait-ForTunnelUp already proved this reverse
    # port for THIS Connect's SessionBgTunnel. Within 30s (same TTL as ENSURE recent_success /
    # PUSH_CONF session_tunnel_fresh), skip Get-TunnelBanner (~0.6-1.5s). Distinct from the
    # generic TunnelBannerCache 3s hit below - requires LastTunnelSpawnSuccess* + live pid.
    if ($script:LastTunnelSpawnSuccessAt -and
        $script:LastTunnelSpawnSuccessPort -eq $Port -and
        $script:LastTunnelSpawnPid -and
        $script:SessionBgTunnel) {
        $bgAlive = $false
        try { $bgAlive = -not $script:SessionBgTunnel.HasExited } catch { $bgAlive = $false }
        if ($bgAlive -and [int]$script:SessionBgTunnel.Id -eq [int]$script:LastTunnelSpawnPid -and
            ((Get-Date) - $script:LastTunnelSpawnSuccessAt).TotalSeconds -lt 30) {
            $script:TunnelSoftFailCount = 0
            Write-GitModeLog "TUNNEL_UP port=$Port up=True reason=session_tunnel_fresh pid=$($script:LastTunnelSpawnPid)" 'TRACE'
            return $true
        }
    }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt -and $script:TunnelBannerCacheUp) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            $script:TunnelSoftFailCount = 0
            Write-GitModeLog "TUNNEL_UP port=$Port up=True banner=$($script:TunnelBannerCacheBanner) cache=1" 'TRACE'
            return $true
        }
    }
    $attempts = 1 + [Math]::Max(0, $Retries)
    $banner = ''
    for ($a = 1; $a -le $attempts; $a++) {
        if ($a -gt 1) {
            Start-Sleep -Milliseconds 250
        }
        $banner = Get-TunnelBanner
        if (Test-TunnelBannerIsWindows -Banner $banner) {
            $script:TunnelSoftFailCount = 0
            Write-GitModeLog "TUNNEL_UP port=$Port up=True banner=$banner attempt=$a" 'TRACE'
            return $true
        }
    }
    Write-GitModeLog "TUNNEL_UP port=$Port up=False banner=$banner attempts=$attempts" 'TRACE'
    return $false
}

function Test-Tunnel {
    return (Test-TunnelUp)
}

function Get-TunnelSshProcess {
    # Bug 51: soft-fail path used to CIM-scan all ssh.exe ~every 800ms - cache briefly.
    if (-not $Port) { return $null }
    $ttlMs = 2000
    if ($script:TunnelSshCimCachePort -eq $Port -and $script:TunnelSshCimCacheAt) {
        $age = [int]((Get-Date) - $script:TunnelSshCimCacheAt).TotalMilliseconds
        if ($age -ge 0 -and $age -lt $ttlMs) {
            return $script:TunnelSshCimCache
        }
    }
    $hit = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { Test-LocalTunnelSshCommandLine -CommandLine $_.CommandLine -TargetPort $Port } |
        Select-Object -First 1
    $script:TunnelSshCimCache = $hit
    $script:TunnelSshCimCacheAt = Get-Date
    $script:TunnelSshCimCachePort = $Port
    return $hit
}

function Try-ReattachSessionTunnelProcess {
    param([ref]$BgTunnel)
    $cim = Get-TunnelSshProcess
    if (-not $cim) { return $false }
    try {
        $proc = Get-Process -Id $cim.ProcessId -ErrorAction Stop
        if (-not $proc.HasExited) {
            $BgTunnel.Value = $proc
            $script:SessionBgTunnel = $proc
            $script:TunnelSyncFailCount = 0
            $script:TunnelSoftFailCount = 0
            $script:NoProcKeepAliveSince = $null
            Write-GitModeLog "TUNNEL_SYNC ok=1 reason=reattached pid=$($proc.Id) port=$Port" 'DEBUG'
            return $true
        }
    } catch {
        Write-GitModeLog "TUNNEL_SYNC reattach_fail pid=$($cim.ProcessId) err=$($_.Exception.Message)" 'DEBUG'
    }
    return $false
}

function Sync-SessionTunnelProcess {
    param([ref]$BgTunnel)
    # Owner/service coupling on every Sync tick (D5): zombie owners must release
    # without Ensure churn when backends stay down and xray was expected.
    if (Get-Command Update-CursorProxyOwnerServiceHealth -ErrorAction SilentlyContinue) {
        if (Test-IsCursorProxyOwner) {
            try { Update-CursorProxyOwnerServiceHealth } catch {}
        }
    }
    if ($BgTunnel.Value -and $BgTunnel.Value.HasExited -and $script:LastTunnelExitLoggedPid -ne $BgTunnel.Value.Id) {
        $exitCode = Get-TunnelProcessExitCode -Process $BgTunnel.Value
        Write-GitModeLog "TUNNEL_EXIT pid=$($BgTunnel.Value.Id) port=$Port exit_code=$exitCode reason=sync_observed_exit" 'WARN'
        $script:LastTunnelExitLoggedPid = $BgTunnel.Value.Id
    }

    # Reattach before health checks: an empty banner must not hide a live ssh -R.
    if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
        $null = Try-ReattachSessionTunnelProcess -BgTunnel $BgTunnel
    }
    if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if ($tcpOpen) {
            $script:TunnelSoftFailCount++
            Write-GitModeLog ("TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/$script:TunnelSoftFailBudget port=$Port reason=no_proc_tcp_open$(Get-TunnelSessionDiagSuffix)") 'WARN'
            $null = Try-ReattachSessionTunnelProcess -BgTunnel $BgTunnel
            if ($script:TunnelSoftFailCount -ge $script:TunnelSoftFailBudget) {
                # TCP still open => reverse forward is alive; Process handle was lost
                # (common with dual UI / re-parent). Do NOT Release-StaleTunnelPort or
                # force session recovery ("Connection dropped") - keep soft-health.
                $dropPid = 0
                if ($BgTunnel.Value) { $dropPid = $BgTunnel.Value.Id }
                elseif ($script:LastTunnelExitLoggedPid) { $dropPid = $script:LastTunnelExitLoggedPid }
                Write-GitModeLog ("TUNNEL_SYNC soft_fail_exhausted_keep_alive port=$Port reason=no_proc_tcp_open pid=$dropPid$(Get-TunnelSessionDiagSuffix)") 'WARN'
                $script:TunnelSoftFailCount = 0; $script:TunnelSyncFailCount = 0
                if (Test-NoProcShouldKeepAlive) { return $true }
                Write-GitModeLog ("TUNNEL_SYNC soft_fail_exhausted_zombie_drop port=$Port reason=no_proc_tcp_open pid=$dropPid$(Get-TunnelSessionDiagSuffix)") 'WARN'
                Write-TunnelDropLog -Reason 'soft_fail_exhausted_zombie_drop' -TunnelPid $dropPid -TcpOpen $true
                Release-StaleTunnelPort
                $script:NoProcKeepAliveSince = $null
                if (Get-Command Update-CursorProxyOwnerServiceHealth -ErrorAction SilentlyContinue) {
                    if (Test-IsCursorProxyOwner) {
                        try { Update-CursorProxyOwnerServiceHealth } catch {}
                    }
                }
                return $false
            }
            $script:TunnelSyncFailCount = 0
            if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
                return $true
            }
            # Reattached under budget: continue into bg-alive probe path.
        }
    }

    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        $now = Get-Date
        if (-not $script:LastForwardProbeAt) {
            $script:LastForwardProbeAt = $now
        } elseif (($now - $script:LastForwardProbeAt).TotalSeconds -ge $script:TunnelForwardProbeIntervalSec) {
            $script:LastForwardProbeAt = $now
            if ($script:TunnelSoftFailCount -eq 0 -and $script:TunnelBannerCacheUp -and [int]$script:TunnelBannerDeferCount -lt 1) {
                $script:TunnelBannerDeferCount++
                Write-GitModeLog "TUNNEL_SYNC probe_deferred count=$script:TunnelBannerDeferCount reason=keepalive_banner_fresh pid=$($BgTunnel.Value.Id) port=$Port" 'DEBUG'
                # skip Test-TunnelUp this tick; still return $true (bg alive) below
            } else {
                $script:TunnelBannerDeferCount = 0
                $probeUp = $false
                $attempts = if ($script:TunnelSoftFailCount -gt 0) { 3 } else { 1 }
                for ($i = 1; $i -le $attempts; $i++) {
                    if ($i -gt 1) { Start-Sleep -Milliseconds 300 }
                    if (Test-TunnelUp) { $probeUp = $true; break }
                }
                if (-not $probeUp) {
                    $tcpOpen = $false
                    try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
                    if ($tcpOpen) {
                        $script:TunnelSoftFailCount++
                        Write-GitModeLog ("TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/$script:TunnelSoftFailBudget pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open$(Get-TunnelSessionDiagSuffix)") 'WARN'
                        $script:TunnelSyncFailCount = 0
                        if ($script:TunnelSoftFailCount -ge $script:TunnelSoftFailBudget) {
                            Write-TunnelDropLog -Reason 'banner_miss_tcp_open_budget' -TunnelPid $BgTunnel.Value.Id `
                                -TcpOpen $true -Banner $script:TunnelBannerCacheBanner
                            Release-StaleTunnelPort
                            $script:TunnelSoftFailCount = 0
                            return $false
                        }
                        return $true
                    } else {
                        $script:TunnelSyncFailCount++
                        $probeBanner = $script:TunnelBannerCacheBanner
                        if ($script:TunnelSyncFailCount -lt 3) {
                            $script:LastForwardProbeAt = (Get-Date).AddSeconds(-$script:TunnelForwardProbeIntervalSec)
                            Write-GitModeLog "TUNNEL_SYNC miss=$script:TunnelSyncFailCount/3 pid=$($BgTunnel.Value.Id) port=$Port reason=bg_alive_forward_dead" 'DEBUG'
                            return $true
                        }
                        Write-TunnelDropLog -Reason 'bg_alive_forward_dead' -TunnelPid $BgTunnel.Value.Id `
                            -TcpOpen $false -Banner $probeBanner
                        Release-StaleTunnelPort
                        $script:TunnelSoftFailCount = 0
                        return $false
                    }
                } else {
                    $script:TunnelSyncFailCount = 0
                    $script:TunnelSoftFailCount = 0
                }
            }
        }
        # Throttle TRACE: the session loop runs far more often than this is useful.
        $nowTs = Get-Date
        if (-not $script:LastTunnelSyncTraceAt -or ($nowTs - $script:LastTunnelSyncTraceAt).TotalSeconds -ge 30) {
            Write-GitModeLog "TUNNEL_SYNC: bg_alive pid=$($BgTunnel.Value.Id) port=$Port" 'TRACE'
            $script:LastTunnelSyncTraceAt = $nowTs
        }
        # Do not reset TunnelSoftFailCount here - only a healthy banner probe may.
        return $true
    }

    if (Test-TunnelUp -Retries 2) {
        $script:TunnelSyncFailCount = 0
        Write-GitModeLog "TUNNEL_SYNC ok=1 reason=tunnel_up_no_ssh_proc port=$Port" 'TRACE'
        return $true
    }
    $script:TunnelSyncFailCount++
    if ($script:TunnelSyncFailCount -lt 3) {
        Write-GitModeLog "TUNNEL_SYNC miss=$script:TunnelSyncFailCount/3 port=$Port reason=tunnel_down_debounce" 'DEBUG'
        return $true
    }
    Write-GitModeLog ("TUNNEL_SYNC ok=0 reason=tunnel_down port=$Port misses=$script:TunnelSyncFailCount$(Get-TunnelSessionDiagSuffix)") 'DEBUG'
    $script:LastTunnelSyncDropReason = 'tunnel_down'
    $script:TunnelSoftFailCount = 0
    return $false
}

function Wait-ForTunnelUp {
    param(
        [System.Diagnostics.Process]$TunnelProc,
        [switch]$Quiet
    )
    $localRNotOwned = $false
    if (-not $script:TunnelWaitMaxAttempts) { $script:TunnelWaitMaxAttempts = 6 }
    $maxAttempts = [int]$script:TunnelWaitMaxAttempts
    if ($maxAttempts -lt 1) { $maxAttempts = 6 }
    for ($i = 1; $i -le $maxAttempts; $i++) {
        if ($TunnelProc -and $TunnelProc.HasExited) {
            $exitCode = Get-TunnelProcessExitCode -Process $TunnelProc
            Write-GitModeLog "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$($TunnelProc.Id) exit_code=$exitCode" 'WARN'
            if (-not $Quiet) { Write-Host '    Tunnel check... SSH process died' -ForegroundColor Red }
            Release-StaleTunnelPort
            return $false
        }
        $up = Test-TunnelUp
        if ($up) {
            # Gate A: banner/TCP alone is not enough — spawn pid must own local -R.
            # Empty local PID list is failure (fail-closed), not success.
            $spawnPid = 0
            if ($TunnelProc) { $spawnPid = [int]$TunnelProc.Id }
            $localPids = @(Get-LocalTunnelSshPids -TargetPort $Port)
            if (($spawnPid -gt 0) -and ($localPids -contains $spawnPid)) {
                Write-GitModeLog "TUNNEL_WAIT ok=1 attempt=$i port=$Port pid=$spawnPid" 'DEBUG'
                if (-not $Quiet) {
                    $label = if ($i -eq 1) { '    Tunnel check...' } else { "    Tunnel check $i/$maxAttempts..." }
                    Write-Host -NoNewline $label -ForegroundColor DarkGray
                    Write-Host " port $Port is open" -ForegroundColor Green
                }
                return $true
            }
            $localRNotOwned = $true
            $localJoined = ($localPids -join ',')
            Write-GitModeLog "TUNNEL_WAIT ok=0 attempt=$i reason=local_r_not_owned port=$Port pid=$spawnPid local_pids=$localJoined" 'WARN'
            if (-not $Quiet) {
                Write-Host "    Tunnel check $i/$maxAttempts... port $Port open but not owned by this tunnel" -ForegroundColor DarkGray
            }
        } elseif (-not $Quiet) {
            Write-Host "    Tunnel check $i/$maxAttempts... port $Port not open yet" -ForegroundColor DarkGray
        }
        if ($i -ge $maxAttempts) { break }
        $sleepSec = [math]::Min(1.5, 0.25 + ($i - 1) * 0.2)
        if (-not $up) {
            Write-GitModeLog "TUNNEL_WAIT ok=0 attempt=$i port=$Port" 'TRACE'
        }
        Start-Sleep -Seconds $sleepSec
    }
    if ($localRNotOwned) {
        Write-GitModeLog "TUNNEL_WAIT fail=1 reason=local_r_not_owned port=$Port pid=$($TunnelProc.Id)" 'WARN'
    } else {
        Write-GitModeLog "TUNNEL_WAIT fail=1 reason=timeout port=$Port" 'WARN'
    }
    Release-StaleTunnelPort
    return $false
}

function Stop-SessionTunnelCleanup {
    param(
        [ref]$BgTunnel,
        [switch]$ClearServerForward
    )
    $killed = @()
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Write-GitModeLog "TUNNEL_STOP: killing bg pid=$($BgTunnel.Value.Id) port=$Port" 'DEBUG'
        Stop-TunnelProcessWithExitLog -ProcessId $BgTunnel.Value.Id -Reason 'session_cleanup'
        $killed += [int]$BgTunnel.Value.Id
    }
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $sessId = [int]$script:SessionBgTunnel.Id
        if ($killed -notcontains $sessId) {
            Write-GitModeLog "TUNNEL_STOP: killing session bg pid=$sessId port=$Port" 'DEBUG'
            Stop-TunnelProcessWithExitLog -ProcessId $sessId -Reason 'session_cleanup'
            $killed += $sessId
        }
    }
    if ($Port) {
        foreach ($processId in (Get-LocalTunnelSshPids -TargetPort $Port)) {
            if ($killed -contains $processId) { continue }
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) {
                Write-GitModeLog "TUNNEL_STOP: skip_peer_live pid=$processId port=$Port" 'DEBUG'
            }
        }
    }
    if ($ClearServerForward -and $Port) { Clear-ServerStaleTunnelForward -TargetPort $Port }
    $BgTunnel.Value = $null
    $script:SessionBgTunnel = $null
    Clear-TunnelBannerCache
}

function Get-ClaudeMountSrc {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    $direct = Join-Path $ConnectScriptDir 'claude-mount.sh'
    if (Test-Path $direct) { return $direct }
    foreach ($rel in @('mac\claude-mount.sh', '..\mac\claude-mount.sh')) {
        try {
            $p = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path $p) { return $p }
        } catch { }
    }
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if ($dir) {
        $src = Join-Path $dir 'claude-mount.sh'
        if (Test-Path $src) { return $src }
    }
    return $null
}

function Get-LfNormalizedShCopy {
    param([Parameter(Mandatory)][string]$Src)
    if (-not (Test-Path $Src)) { return $Src }
    $raw = [System.IO.File]::ReadAllText($Src)
    if ($raw -notmatch "`r") { return $Src }
    # Unique per-process temp name: multiple connect.ps1 windows can be open at once (this is
    # a supported, normal pattern, not an edge case), and a fixed filename here meant two
    # concurrent sessions raced on the SAME temp file - one process's write could land mid another's
    # read, producing a corrupt/partial hash or a file-in-use failure that cascaded into a
    # confusing null-reference exception several steps later.
    $tmp = Join-Path $env:TEMP ("claude-lf-{0}-{1}" -f $PID, [System.IO.Path]::GetFileName($Src))
    [System.IO.File]::WriteAllText($tmp, ($raw -replace "`r`n", "`n" -replace "`r", "`n"))
    return $tmp
}

function Push-ClaudeMountIfChanged {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Alias
    )
    if (-not (Test-Path $Src)) { return }
    $uploadSrc = Get-LfNormalizedShCopy -Src $Src
    $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
    $remoteHash = ((SshX "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}'") -join '').Trim()
    if ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower())) { return }
    # claude-mount is live-executed (claude-watchdog polls it every 30s) - scp to a
    # .new sibling and mv into place atomically so a concurrent exec never tears it.
    scp -o BatchMode=yes -o ConnectTimeout=20 -q $uploadSrc "${Alias}:~/.local/bin/claude-mount.new" 2>$null
    if ($LASTEXITCODE -eq 0) {
        SshX 'sed -i "s/\r$//" ~/.local/bin/claude-mount.new 2>/dev/null; chmod +x ~/.local/bin/claude-mount.new && mv -f ~/.local/bin/claude-mount.new ~/.local/bin/claude-mount' 2>$null | Out-Null
    }
}

function Prepare-ServerSessionParallel {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$MountSrc = '',
        [Parameter(Mandatory)][string]$Alias
    )
    $script:ActiveProjectId = $ProjectId
    $prepareBegin = Get-Date
    Write-GitModeLog "PREPARE_SESSION: begin project=$ProjectId" 'DEBUG'
    $scpProc = $null
    $scpBegin = $null
    $needScp = $false
    if ($MountSrc -and (Test-Path $MountSrc)) {
        $uploadSrc = Get-LfNormalizedShCopy -Src $MountSrc
        $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
        if ($localHash -and $script:ClaudeMountSyncVerifiedHash -eq $localHash) {
            # Already confirmed in sync earlier this session (e.g. an earlier project
            # switch) - the local source and remote file can't have silently drifted
            # in between, so skip the sha256sum SSH round trip (~500-700ms) on every
            # subsequent project pick.
            Write-GitModeLog "SCP: skip_verified project=$ProjectId hash=$localHash" 'TRACE'
            $needScp = $false
        } else {
            $remoteHash = ((SshX "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}'") -join '').Trim()
            $needScp = -not ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower()))
            if (-not $needScp -and $localHash) { $script:ClaudeMountSyncVerifiedHash = $localHash }
        }
        if ($needScp) {
            Write-GitModeLog "SCP: begin project=$ProjectId alias=$Alias" 'DEBUG'
            # Bug 50: Start-Job + Stop-Job can orphan native scp - Start-Process + tree kill.
            # claude-mount is live-executed (watchdog polls every 30s) - land in a .new
            # sibling and mv atomically below so a concurrent exec never tears it.
            $scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=20','-q', $uploadSrc, "${Alias}:~/.local/bin/claude-mount.new")
            $scpProc = Start-Process -FilePath 'scp' -ArgumentList $scpArgs -NoNewWindow -PassThru
            $scpBegin = Get-Date
        }
    }
    Push-ServerConnectConf -ActiveMount $ProjectId
    if ($scpProc) {
        if (-not $scpProc.WaitForExit(30000)) {
            $scpMs = [int]((Get-Date) - $scpBegin).TotalMilliseconds
            Write-GitModeLog "SCP: timeout ERROR project=$ProjectId ms=$scpMs" 'ERROR'
            $scpPid = 0
            try { $scpPid = [int]$scpProc.Id } catch { }
            if ($scpPid -gt 0) {
                try {
                    Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', "$scpPid", '/T', '/F') `
                        -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
                } catch { }
            }
            try { if (-not $scpProc.HasExited) { $scpProc.Kill() } } catch { }
            try { $null = $scpProc.WaitForExit(3000) } catch { }
        } else {
            $scpExit = 1
            try { if ($null -ne $scpProc.ExitCode) { $scpExit = [int]$scpProc.ExitCode } } catch { }
            $scpMs = [int]((Get-Date) - $scpBegin).TotalMilliseconds
            Write-GitModeLog "SCP: end project=$ProjectId exit=$scpExit ms=$scpMs" 'DEBUG'
            if ($scpExit -eq 0) {
                SshX 'sed -i "s/\r$//" ~/.local/bin/claude-mount.new 2>/dev/null; chmod +x ~/.local/bin/claude-mount.new && mv -f ~/.local/bin/claude-mount.new ~/.local/bin/claude-mount' 2>$null | Out-Null
                if ($localHash) { $script:ClaudeMountSyncVerifiedHash = $localHash }
            }
        }
    }
    $prepareMs = [int]((Get-Date) - $prepareBegin).TotalMilliseconds
    Write-GitModeLog "PREPARE_SESSION: end project=$ProjectId ms=$prepareMs" 'DEBUG'
}

function Test-ProjectMountHealthy {
    param([Parameter(Mandatory)][string]$ProjectId)
    # Bound the remote check - a wedged sshfs/fcb can otherwise hang SshX with no UI step.
    $out = ((SshX "timeout 12 $CM check '$ProjectId' 2>/dev/null" -NoRetryOnTimeout) -join '').Trim()
    return ($out -eq 'ok')
}

function Clear-ServerTunnelKnownHost {
    if (-not $Port) { return }
    # Probe + claude-mount sshfs both use known_hosts_claude_mount; tunnel file is legacy.
    # Truncate dedicated files so a rotated laptop sshd host key cannot loop forever.
    SshX "ssh-keygen -f `$HOME/.ssh/known_hosts -R '[127.0.0.1]:${Port}' 2>/dev/null || true; ssh-keygen -f `$HOME/.ssh/known_hosts -R '127.0.0.1' 2>/dev/null || true; : > `$HOME/.ssh/known_hosts_claude_mount 2>/dev/null || true; : > `$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null || true; chmod 600 `$HOME/.ssh/known_hosts_claude_mount `$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null || true; true" 2>$null | Out-Null
}

function Invoke-LaptopReverseSshProbe {
    $probeBegin = Get-Date
    Write-GitModeLog "LAPTOP_SSH: probe begin port=$Port user=$LaptopUser" 'TRACE'
    $script:LastLaptopReverseSshError = ''
    if (-not $Port -or -not $LaptopUser) {
        $script:LastLaptopReverseSshError = 'missing TUNNEL_PORT or LAPTOP_USER'
        $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: probe end ok=0 ms=$probeMs err=$($script:LastLaptopReverseSshError)" 'DEBUG'
        return $false
    }
    if (-not (Test-TunnelUp)) {
        $script:LastLaptopReverseSshError = "tunnel port $Port not open on server"
        $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: probe end ok=0 ms=$probeMs err=$($script:LastLaptopReverseSshError)" 'DEBUG'
        return $false
    }
    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    # Batch touch+chmod+probe into one SSH (was 2 round-trips ~1.2s).
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $out = (SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null; timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command exit 2>&1") -join "`n"
        if ($LASTEXITCODE -eq 0) {
            $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
            Write-GitModeLog "LAPTOP_SSH: probe end ok=1 ms=$probeMs attempt=$attempt" 'DEBUG'
            try {
                $fpNow = Get-TunnelHostKeyFingerprint -TargetPort ([int]$Port)
                if ($fpNow) { Save-LaptopHostKeyFingerprint -Fingerprint $fpNow }
            } catch { }
            return $true
        }
        if ($attempt -eq 1 -and ($out -match 'Host key verification failed|HOST IDENTIFICATION HAS CHANGED|Offending|system administrator')) {
            Clear-ServerTunnelKnownHost
            continue
        }
        break
    }
    $detail = @($out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -match 'Permission denied|Host key verification failed|Connection refused|Could not resolve|No route|authenticity of host|Please contact your system administrator|publickey|reset by peer'
    }) -join ' '
    if (-not $detail) {
        $detail = @($out -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)[0]
    }
    if (-not $detail) { $detail = "server ssh exit $LASTEXITCODE" }
    $script:LastLaptopReverseSshError = $detail
    $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
    Write-GitModeLog "LAPTOP_SSH: probe end ok=0 ms=$probeMs err=$detail" 'DEBUG'
    return $false
}

function Test-LaptopReverseSsh {
    return (Invoke-LaptopReverseSshProbe)
}

function Ensure-LaptopReverseSsh {
    param([string]$PubB = '')
    $ensureBegin = Get-Date
    Write-GitModeLog 'LAPTOP_SSH: ensure_begin' 'DEBUG'
    if (-not (Ensure-LaptopSshReady -PubB $PubB)) {
        $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_end rc=2 ms=$ensureMs reason=laptop_ssh_not_ready" 'DEBUG'
        return 2
    }
    Clear-ServerTunnelKnownHost
    if (Test-LaptopReverseSsh) {
        $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_end rc=0 ms=$ensureMs" 'DEBUG'
        return 0
    }
    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    if ($uidStr -and (Acquire-TunnelPort -UidStr $uidStr)) {
        Clear-ServerTunnelKnownHost
        if (Test-LaptopReverseSsh) {
            $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
            Write-GitModeLog "LAPTOP_SSH: ensure_end rc=0 ms=$ensureMs reason=acquired_port" 'DEBUG'
            return 0
        }
    }
    Release-StaleTunnelPort
    Clear-ServerTunnelKnownHost
    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
        $restartBegin = Get-Date
        Write-GitModeLog 'LAPTOP_SSH: restart_sshd begin' 'DEBUG'
        Restart-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $restartMs = [int]((Get-Date) - $restartBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: restart_sshd end ms=$restartMs" 'DEBUG'
    }
    Clear-ServerTunnelKnownHost
    if (Test-LaptopReverseSsh) {
        $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_end rc=0 ms=$ensureMs reason=after_sshd_restart" 'DEBUG'
        return 0
    }
    $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
    Write-GitModeLog "LAPTOP_SSH: ensure_end rc=1 ms=$ensureMs err=$($script:LastLaptopReverseSshError)" 'WARN'
    return 1
}

function Ensure-LaptopReverseSshCached {
    param([string]$PubB = '')
    $cachedBegin = Get-Date
    Write-GitModeLog "LAPTOP_SSH: ensure_cached begin verified=$($script:LaptopSshVerified)" 'TRACE'
    # Real cache: once verified this session and the forward tunnel is still up, skip the
    # reverse-SSH probe (~1s). Re-probe only on first hit / tunnel change / auth fail.
    if ($script:LaptopSshVerified -and (Test-TunnelUp)) {
        $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=0 ms=$cachedMs reason=verified_tunnel_up" 'TRACE'
        return 0
    }
    if ($script:LaptopSshVerified -and (Test-LaptopReverseSsh)) {
        $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=0 ms=$cachedMs reason=verified_cache" 'TRACE'
        return 0
    }
    # Session-fresh (2026-07-25): ENSURE Wait-ForTunnelUp already saw a Windows OpenSSH
    # banner on this reverse port for SessionBgTunnel. Within 30s skip the duplicate
    # reverse probe (~1.3-2.7s) that "Verifying laptop SSH" used to pay.
    # Do NOT require TunnelBannerCacheUp: Invoke-RecoverIfNeeded clears that cache on
    # need_mount (live 2026-07-25 afb01e2a81b1: reason=probe_ok ms=2725 after recover).
    # Spawn stamps + live SessionBgTunnel pid are the trust signal (same as PUSH_CONF).
    # Does NOT skip when spawn markers are absent (cold / foreign / reseed must still probe).
    if (-not $script:LaptopSshVerified -and $Port -and $script:LastTunnelSpawnSuccessAt -and
        $script:LastTunnelSpawnSuccessPort -eq $Port -and
        $script:LastTunnelSpawnPid -and
        $script:SessionBgTunnel) {
        $bgAlive = $false
        try { $bgAlive = -not $script:SessionBgTunnel.HasExited } catch { $bgAlive = $false }
        if ($bgAlive -and [int]$script:SessionBgTunnel.Id -eq [int]$script:LastTunnelSpawnPid -and
            ((Get-Date) - $script:LastTunnelSpawnSuccessAt).TotalSeconds -lt 30) {
            $script:LaptopSshVerified = $true
            $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
            Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=0 ms=$cachedMs reason=session_tunnel_fresh" 'TRACE'
            return 0
        }
    }
    if (Test-LaptopReverseSsh) {
        $script:LaptopSshVerified = $true
        $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=0 ms=$cachedMs reason=probe_ok" 'TRACE'
        return 0
    }
    $rc = Ensure-LaptopReverseSsh -PubB $PubB
    if ($rc -eq 0) { $script:LaptopSshVerified = $true }
    else { $script:LaptopSshVerified = $false }
    $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
    Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=$rc ms=$cachedMs" 'DEBUG'
    return $rc
}

function Invoke-RecoverIfNeeded {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [switch]$FreshTunnel
    )
    # Returns whether the mount was already healthy (the `check` probe result) so a caller can
    # pass it on to Invoke-MountProject as a same-iteration hint and skip a redundant second
    # `check` SSH round-trip - it must NEVER be used to skip the `$CM up` call itself, because
    # that call is what re-applies git hide/stubs.
    # FreshTunnel used to skip the health check and always run recover-one (~1s+ SSH), even when
    # the mount was already healthy after a new tunnel. Always check first; recover only if unhealthy.
    $checkOk = Test-ProjectMountHealthy -ProjectId $ProjectId
    if ($checkOk) {
        # No separate "off_mode_apply" SSH call here: Invoke-MountProject's own `$CM up` call,
        # which always runs moments later in this same flow regardless of this function's
        # result, ALREADY unconditionally re-applies _hide_git_and_create_stubs on its
        # "already mounted" fast path (verified server-side in claude-mount.sh's _do_mount:
        # the GIT_MODE=off branch calls _hide_git_and_create_stubs every time, not just on a
        # fresh mount). Running recover-if-needed here duplicated that exact work for a full
        # extra SSH round-trip (was costing ~3s) for zero additional effect.
        Write-GitModeLog "RECOVER: skip project=$ProjectId reason=mount_ok fresh_tunnel=$FreshTunnel" 'DEBUG'
        return $checkOk
    }
    $recoverBegin = Get-Date
    Write-GitModeLog "RECOVER: begin project=$ProjectId fresh_tunnel=$FreshTunnel" 'DEBUG'
    Write-Host '      -> recovering stale mounts...' -ForegroundColor DarkGray
    Clear-TunnelBannerCache
    # Same trust flags as the healthy-mount path above and Invoke-MountProject's `up` call -
    # the tunnel was already confirmed earlier this same flow, so skip redundant reverse-SSH
    # tunnel-liveness re-checks inside claude-mount.sh's recovery commands too (this path
    # previously never got the fix applied to the (now-removed) off_mode_apply call).
    $bannerOk = if ($script:TunnelBannerCacheUp) { 'CLAUDE_TUNNEL_BANNER_OK=1 ' } else { '' }
    SshX "timeout 30 CLAUDE_TRUSTED_TUNNEL=1 ${bannerOk}$CM recover-one '$ProjectId' 2>/dev/null || timeout 30 CLAUDE_TRUSTED_TUNNEL=1 ${bannerOk}$CM recover-if-needed '$ProjectId' 2>/dev/null || timeout 30 CLAUDE_TRUSTED_TUNNEL=1 ${bannerOk}$CM recover 2>/dev/null || true" 2>$null | Out-Null
    $recoverMs = [int]((Get-Date) - $recoverBegin).TotalMilliseconds
    Write-GitModeLog "RECOVER: end project=$ProjectId ms=$recoverMs" 'DEBUG'
    return $checkOk
}

function Ensure-SessionTunnel {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = '',
        [ref]$BgTunnel,
        [ref]$TunnelReused,
        [switch]$WaitQuiet
    )
    $TunnelReused.Value = $false
    $skipAdoptAfterSoftFail = $false
    if ((-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) -and
        $script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $BgTunnel.Value = $script:SessionBgTunnel
    }
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        if (Test-TunnelUp) {
            $TunnelReused.Value = $true
            $script:TunnelSyncFailCount = 0
            Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$($BgTunnel.Value.Id) port=$Port reason=tunnel_up" 'DEBUG'
            Set-SocksProxyPortOnReuse -TunnelPid $BgTunnel.Value.Id -Alias $Alias -SshCfgPath $SshCfgPath
            if (-not (Test-ProxyReseedShouldKill -TunnelPid $BgTunnel.Value.Id -Alias $Alias -SshCfgPath $SshCfgPath)) {
                Complete-CursorProxyAfterTunnel
                return $true
            }
            # Fall through: kill + reseed with -L proxy leg (ReseedEffective only)
            $TunnelReused.Value = $false
            $skipAdoptAfterSoftFail = $true
        }
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if ($tcpOpen -and -not $skipAdoptAfterSoftFail) {
            # Banner miss + TCP open often races right after spawn (Initialize then session-loop
            # Ensure). Prefer recent_success over kill/reseed (~7s waste per pick).
            if ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
                $script:LastTunnelSpawnPid -eq $BgTunnel.Value.Id -and
                ((Get-Date) - $script:LastTunnelSpawnSuccessAt).TotalSeconds -lt 30) {
                $TunnelReused.Value = $true
                $script:TunnelSyncFailCount = 0
                Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$($BgTunnel.Value.Id) port=$Port reason=recent_success_tcp_open" 'DEBUG'
                Set-SocksProxyPortOnReuse -TunnelPid $BgTunnel.Value.Id -Alias $Alias -SshCfgPath $SshCfgPath
                if (-not (Test-ProxyReseedShouldKill -TunnelPid $BgTunnel.Value.Id -Alias $Alias -SshCfgPath $SshCfgPath)) {
                    Complete-CursorProxyAfterTunnel
                    return $true
                }
                $TunnelReused.Value = $false
                $skipAdoptAfterSoftFail = $true
            }
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            $script:TunnelSoftFailCount++
            Write-GitModeLog ("ENSURE_TUNNEL soft_fail count=$script:TunnelSoftFailCount/$script:TunnelSoftFailBudget pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed$(Get-TunnelSessionDiagSuffix)") 'WARN'
            if ($script:TunnelSoftFailCount -ge $script:TunnelSoftFailBudget) {
                Write-TunnelDropLog -Reason 'banner_miss_tcp_open_budget' -TunnelPid $BgTunnel.Value.Id `
                    -TcpOpen $true -Banner $script:TunnelBannerCacheBanner
                Release-StaleTunnelPort
                $script:TunnelSoftFailCount = 0
                return $false
            }
            # Fall through to kill/reseed - must NOT adopt the same local -R (that defeated reseed).
            $skipAdoptAfterSoftFail = $true
        } elseif ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
            $script:LastTunnelSpawnPid -eq $BgTunnel.Value.Id -and
            ((Get-Date) - $script:LastTunnelSpawnSuccessAt).TotalSeconds -lt 5) {
            $TunnelReused.Value = $true
            Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$($BgTunnel.Value.Id) port=$Port reason=recent_success" 'DEBUG'
            Set-SocksProxyPortOnReuse -TunnelPid $BgTunnel.Value.Id -Alias $Alias -SshCfgPath $SshCfgPath
            if (-not (Test-ProxyReseedShouldKill -TunnelPid $BgTunnel.Value.Id -Alias $Alias -SshCfgPath $SshCfgPath)) {
                Complete-CursorProxyAfterTunnel
                return $true
            }
            # Fall through: kill + reseed with -L proxy leg (ReseedEffective only)
            $TunnelReused.Value = $false
        }
    }

        # Fast adopt: local ssh -R already forwarding $Port and server TCP is open.
    if ($Port -and -not $skipAdoptAfterSoftFail) {
        $adoptPids = @(Get-LocalTunnelSshPids -TargetPort $Port)
        if ($adoptPids.Count -gt 0) {
            $tcpOpen = $false
            try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
            if ($tcpOpen) {
                $adoptPid = [int]$adoptPids[0]
                $adoptProc = Get-Process -Id $adoptPid -ErrorAction SilentlyContinue
                if ($adoptProc -and -not $adoptProc.HasExited) {
                    $BgTunnel.Value = $adoptProc
                    $script:SessionBgTunnel = $adoptProc
                    $TunnelReused.Value = $true
                    $script:TunnelSyncFailCount = 0
                    $script:TunnelSoftFailCount = 0
                    Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$adoptPid port=$Port reason=adopt_local_forward" 'INFO'
                    Set-SocksProxyPortOnReuse -TunnelPid $adoptPid -Alias $Alias -SshCfgPath $SshCfgPath
                    if (-not (Test-ProxyReseedShouldKill -TunnelPid $adoptPid -Alias $Alias -SshCfgPath $SshCfgPath)) {
                        Complete-CursorProxyAfterTunnel
                        return $true
                    }
                    # Fall through: kill + reseed with -L proxy leg (ReseedEffective only)
                    $TunnelReused.Value = $false
                    $skipAdoptAfterSoftFail = $true
                }
            }
        }
    }
    Write-GitModeLog "ENSURE_TUNNEL start port=$Port alias=$Alias had_bg=$([bool]$BgTunnel.Value)" 'DEBUG'
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Write-GitModeLog "ENSURE_TUNNEL killing stale bg pid=$($BgTunnel.Value.Id)" 'DEBUG'
        Clear-TunnelBannerCache
        Stop-TunnelProcessWithExitLog -ProcessId $BgTunnel.Value.Id -Reason 'ensure_stale_bg'
        if ($Port) { Clear-ServerStaleTunnelForward -TargetPort $Port }
    }

    $protectedPids = @()
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $protectedPids += [int]$script:SessionBgTunnel.Id
    }
    if ($Port) {
        Remove-LocalOrphanTunnel -TargetPort $Port -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids
    }

        if (-not $script:ServerUidStr) {
            $script:ServerUidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
        }
        $uidStr = $script:ServerUidStr
    # Fast path: Port already chosen (Initialize-ServerSession / prior Ensure). Re-scanning
    # all slots costs ~5s per call and was the main cold-connect delay.
    if ($uidStr -and -not $Port) {
        $null = Acquire-TunnelPort -UidStr $uidStr -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids
        Write-GitModeLog "ENSURE_TUNNEL acquire_empty_port done port=$Port" 'DEBUG'
    } elseif ($uidStr -and $Port) {
        Write-GitModeLog "ENSURE_TUNNEL skip_acquire port=$Port reason=already_set" 'DEBUG'
    }

    $needStaleClear = $false
    if ($Port) {
        $haveLocal = (@(Get-LocalTunnelSshPids -TargetPort $Port).Count -gt 0)
        if (-not $haveLocal) {
            $tcpOpen2 = $false
            # Reuse the recent acquire/push tcp verdict for this port (still pre-spawn, so the port
            # is unchanged); a live probe still runs on cache miss/expiry.
            try { $tcpOpen2 = [bool](Test-TunnelPortTcpOpen -MaxCacheAgeMs 12000) } catch { $tcpOpen2 = $false }
            if ($tcpOpen2) { $needStaleClear = $true }
        }
    }
    if ($needStaleClear) { Release-StaleTunnelPort }
    else { Write-GitModeLog "ENSURE_TUNNEL skip_release_stale port=$Port" 'DEBUG' }
    if ($SshCfgPath) { Sanitize-SshAliasConfig -CfgPath $SshCfgPath -AliasName $Alias }
    Clear-TunnelBannerCache
    $script:LastForwardProbeAt = $null
    $protectPid = 0
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) { $protectPid = [int]$BgTunnel.Value.Id }
    $socksCandidate = Get-SocksProxyPort
    Clear-LegacyDynamicSocksTunnels -ProtectPid $protectPid -SocksPort $socksCandidate | Out-Null
    $sshArgs = @(
        '-N', '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=5',
        '-R', "$Port`:localhost:22")
    $remoteSocksOk = Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath
    if (-not $remoteSocksOk) {
        # Mirror Add-TunnelHttpProxyLeg: a single Win32-OpenSSH ConnectTimeout burn can look
        # like closed xray and drop -L for the whole tunnel spawn (Aria empty socks_port= live
        # 2026-08-01). Retry once with ForceProbe before clearing proxy legs.
        $remoteSocksOk = Test-RemoteXraySocksOpen -Alias $Alias -SshCfgPath $SshCfgPath -ForceProbe
        if ($remoteSocksOk) {
            Write-GitModeLog "ENSURE_TUNNEL remote_xray_socks=open_on_retry port=$($script:XrayServerSocksPort)" 'INFO'
        }
    }
    $isOwner = $false
    if (Get-Command Claim-CursorProxyOwner -ErrorAction SilentlyContinue) {
        $isOwner = [bool](Claim-CursorProxyOwner)
    } else {
        $isOwner = $true
        $script:CursorProxyOwner = $true
    }
    if (-not $remoteSocksOk) {
        Write-GitModeLog "ENSURE_TUNNEL remote_xray_socks=closed port=$($script:XrayServerSocksPort) skipping_proxy_leg" 'INFO'
        Write-GitModeLog 'PROXY_FALLBACK mode=server_direct reason=xray_closed' 'WARN'
        Write-GitModeLog 'CURSOR_PROXY_MODE mode=server_direct' 'INFO'
        # Clear session legs so Complete-CursorProxyAfterTunnel can skip sidecar thrash.
        # Do NOT leave stale $script:SocksProxyPort from an earlier pick in this process.
        $script:SocksProxyPort = $null
        $script:HttpProxyPort = $null
        $script:SessionTunnelProxyLegs = $false
    } elseif (-not $isOwner) {
        if ((Test-LocalPortOpen -PortNum $socksCandidate) -and (Test-LocalPortOpen -PortNum (Get-HttpProxyPort))) {
            $script:SocksProxyPort = $socksCandidate
            $script:HttpProxyPort = Get-HttpProxyPort
            $script:SessionTunnelProxyLegs = $true
            Write-GitModeLog "ENSURE_TUNNEL proxy_adopt non_owner local=$socksCandidate" 'INFO'
        } else {
            $script:SessionTunnelProxyLegs = $false
            Write-GitModeLog "ENSURE_TUNNEL proxy_skip reason=non_owner_no_listener" 'INFO'
        }
    } elseif (-not (Test-LocalPortFree -PortNum $socksCandidate)) {
        if (Test-LocalPortOpen -PortNum $socksCandidate) {
            $script:SocksProxyPort = $socksCandidate
            $httpCandidate = Get-HttpProxyPort
            if (Test-LocalPortOpen -PortNum $httpCandidate) { $script:HttpProxyPort = $httpCandidate }
            $script:SessionTunnelProxyLegs = $true
            $script:SessionEverHadProxyLegs = $true
            Write-GitModeLog "ENSURE_TUNNEL proxy_adopt busy_healthy local=$socksCandidate" 'INFO'
        } else {
            Clear-LegacyDynamicSocksTunnels -ProtectPid 0 -SocksPort $socksCandidate | Out-Null
            if (Test-LocalPortFree -PortNum $socksCandidate) {
                $sshArgs += @('-L', "127.0.0.1:${socksCandidate}:127.0.0.1:$($script:XrayServerSocksPort)")
                $script:SocksProxyPort = $socksCandidate
                $script:SessionTunnelProxyLegs = $true
                $script:SessionEverHadProxyLegs = $true
                Write-GitModeLog "ENSURE_TUNNEL proxy_leg=-L local=$socksCandidate remote=$($script:XrayServerSocksPort) after_legacy_cleanup" 'INFO'
                $sshArgsList = New-Object 'System.Collections.Generic.List[string]'
                if ($null -ne $sshArgs) { [void]$sshArgsList.AddRange([string[]]@($sshArgs)) }
                Add-TunnelHttpProxyLeg -SshArgs $sshArgsList -Alias $Alias -SshCfgPath $SshCfgPath
                $sshArgs = $sshArgsList.ToArray()
            } else {
                $script:SessionTunnelProxyLegs = $false
                Write-GitModeLog "ENSURE_TUNNEL socks_port_busy port=$socksCandidate skipping_proxy_leg" 'WARN'
            }
        }
    } else {
        $sshArgs += @('-L', "127.0.0.1:${socksCandidate}:127.0.0.1:$($script:XrayServerSocksPort)")
        $script:SocksProxyPort = $socksCandidate
        $script:SessionTunnelProxyLegs = $true
        $script:SessionEverHadProxyLegs = $true
        Write-GitModeLog "ENSURE_TUNNEL proxy_leg=-L local=$socksCandidate remote=$($script:XrayServerSocksPort)" 'INFO'
        $sshArgsList = New-Object 'System.Collections.Generic.List[string]'
        if ($null -ne $sshArgs) { [void]$sshArgsList.AddRange([string[]]@($sshArgs)) }
        Add-TunnelHttpProxyLeg -SshArgs $sshArgsList -Alias $Alias -SshCfgPath $SshCfgPath
        $sshArgs = $sshArgsList.ToArray()
    }
    # -L forwards local loopback to server-side xray SOCKS on the same already-monitored,
    # already-reconnect-handled ssh process as the reverse tunnel (not a second ssh process).
    # Used by editor-launch.ps1 to route Cursor's own network traffic (chat/agent, not just
    # extensions) through xray on the server so it egresses via the VLESS exit IP for
    # every developer, rather than each laptop's own network or the shared office IP.
    # Still-busy: after Clear logged "port still busy", never Start-Process -R on that sticky
    # port (D4). Rebind to another free slot in the user's block; cap consecutive refuse cycles
    # so a renewing still-busy marker can never self-deadlock for ~12 minutes (Incident B).
    if (-not $script:RefuseSpawnStreakCap) { $script:RefuseSpawnStreakCap = 5 }
    if ($null -eq $script:RefuseSpawnStreak) { $script:RefuseSpawnStreak = 0 }
    if (Test-StaleForwardStillBusyAbort -TargetPort $Port) {
        $busyPort = [int]$Port
        Write-GitModeLog "ENSURE_TUNNEL refuse_spawn reason=stale_port_busy port=$busyPort" 'WARN'
        $script:RefuseSpawnStreak = [int]$script:RefuseSpawnStreak + 1
        if ([int]$script:RefuseSpawnStreak -ge [int]$script:RefuseSpawnStreakCap) {
            Write-GitModeLog ("ENSURE_TUNNEL refuse_spawn_streak_exhausted port={0} streak={1} cap={2}" -f $busyPort, $script:RefuseSpawnStreak, $script:RefuseSpawnStreakCap) 'ERROR'
            $BgTunnel.Value = $null
            return $false
        }
        $rebound = $false
        $prevPort = [int]$Port
        $savedSlot = $script:TunnelSlot
        if ($uidStr -and (Get-Command Acquire-TunnelPort -ErrorAction SilentlyContinue)) {
            try {
                $rebound = [bool](Acquire-TunnelPort -UidStr $uidStr -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids)
            } catch { $rebound = $false }
        }
        if ($rebound -and [int]$Port -gt 0 -and [int]$Port -ne $prevPort) {
            Write-GitModeLog ("ENSURE_TUNNEL refuse_spawn reason=stale_port_busy_rebind from={0} to={1} streak={2}" -f $prevPort, $Port, $script:RefuseSpawnStreak) 'WARN'
            $script:LastStaleForwardStillBusyPort = $null
            $script:LastStaleForwardStillBusyAt = $null
            $script:RefuseSpawnStreak = 0
            # Rebuild -R target onto the rebound port (sshArgs was built with busyPort).
            $newArgs = New-Object 'System.Collections.Generic.List[string]'
            $skipNext = $false
            foreach ($a in @($sshArgs)) {
                if ($skipNext) { $skipNext = $false; continue }
                if ($a -eq '-R') {
                    [void]$newArgs.Add('-R')
                    [void]$newArgs.Add("$Port`:localhost:22")
                    $skipNext = $true
                    continue
                }
                [void]$newArgs.Add([string]$a)
            }
            $sshArgs = $newArgs.ToArray()
        } else {
            $script:Port = $prevPort
            $Port = $script:Port
            $script:TunnelSlot = $savedSlot
            Write-GitModeLog ("ENSURE_TUNNEL refuse_spawn reason=stale_port_busy_no_rebind port={0} streak={1}" -f $busyPort, $script:RefuseSpawnStreak) 'WARN'
            $BgTunnel.Value = $null
            return $false
        }
    }
    $BgTunnel.Value = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList ($sshArgs + @($Alias))
    # #P2: tie the reverse-tunnel lifetime to this Connect process via the same
    # KILL_ON_JOB_CLOSE job used for the sidecar tree, so an abrupt exit (X button,
    # crash, force-kill) cannot leave the tunnel process orphaned holding its port.
    if (Get-Command Add-CursorProxySidecarJobProcess -ErrorAction SilentlyContinue) {
        Add-CursorProxySidecarJobProcess -Process $BgTunnel.Value
    }
    # We just started a listener on $Port: any cached pre-spawn "closed" verdict is now stale.
    if (Get-Command Clear-TunnelTcpState -ErrorAction SilentlyContinue) { Clear-TunnelTcpState -Port ([int]$Port) }
    Write-GitModeLog "ENSURE_TUNNEL spawned pid=$($BgTunnel.Value.Id) port=$Port slot=$($script:TunnelSlot) socks_port=$($script:SocksProxyPort) http_port=$($script:HttpProxyPort)" 'INFO'
    if (Wait-ForTunnelUp -TunnelProc $BgTunnel.Value -Quiet:$WaitQuiet) {
        $script:LastTunnelSpawnSuccessAt = Get-Date
        $script:LastTunnelSpawnSuccessPort = $Port
        $script:LastTunnelSpawnPid = $BgTunnel.Value.Id
        $script:TunnelSyncFailCount = 0
        $script:TunnelSoftFailCount = 0
        $script:SessionBgTunnel = $BgTunnel.Value
        $script:TunnelWaitBackoffSec = 2
        $script:TunnelWaitFailStreak = 0
        $script:RefuseSpawnStreak = 0
        Write-GitModeLog "ENSURE_TUNNEL ok=1 pid=$($BgTunnel.Value.Id)" 'INFO'
        Complete-CursorProxyAfterTunnel
        return $true
    }
    $script:TunnelWaitFailStreak = [int]$script:TunnelWaitFailStreak + 1
    if (-not $script:TunnelWaitBackoffSec) { $script:TunnelWaitBackoffSec = 2 }
    Write-GitModeLog ("ENSURE_TUNNEL ok=0 reason=wait_timeout pid={0} streak={1} backoff_sec={2}" -f $BgTunnel.Value.Id, $script:TunnelWaitFailStreak, $script:TunnelWaitBackoffSec) 'WARN'
    if ($script:TunnelWaitFailStreak -ge 6) {
        Write-GitModeLog 'ENSURE_TUNNEL wait_timeout_budget_exhausted surfacing_ui' 'ERROR'
    }
    # Monotonic capped backoff — never skip sleep at high streak (was inverted: streak>=6
    # skipped sleep and produced a flat ~6.5s storm cadence; Incident A ~466 SSH attempts).
    Start-Sleep -Seconds ([int]$script:TunnelWaitBackoffSec)
    $script:TunnelWaitBackoffSec = [Math]::Min(60, [int]$script:TunnelWaitBackoffSec * 2)
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Clear-TunnelBannerCache
        Stop-TunnelProcessWithExitLog -ProcessId $BgTunnel.Value.Id -Reason 'ensure_wait_timeout'
    }
    $BgTunnel.Value = $null
    return $false
}

function Initialize-SessionBgTunnel {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = '',
        [switch]$Quiet
    )
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited -and (Test-TunnelUp)) {
        return $true
    }
    $reused = $false
    $tunnel = $null
    if (Ensure-SessionTunnel -Alias $Alias -SshCfgPath $SshCfgPath -BgTunnel ([ref]$tunnel) -TunnelReused ([ref]$reused) -WaitQuiet:$Quiet) {
        $script:SessionBgTunnel = $tunnel
        return $true
    }
    $script:SessionBgTunnel = $null
    return $false
}

function Warn-ForeignServerSession {
    # Return $true to continue, $false when user aborts a likely wrong-account takeover.
    # Self-heal: stale conf + no listening reverse tunnel -> clear and continue.
    # Speed (stable): one SSH reads conf (+ live port check when foreign), instead of 3-4 greps.
    if (Get-Command Test-WarmLocalConfForeignSkip -ErrorAction SilentlyContinue) {
        if (Test-WarmLocalConfForeignSkip) {
            Write-GitModeLog 'FOREIGN_SESSION skip reason=warm_local_conf' 'DEBUG'
            return $true
        }
    }
    $probeCmd = 'set +e; CONF="$HOME/.claude-connect.conf"; LU=""; OS=""; PORT=""; if [ -f "$CONF" ]; then LU=$(grep -E "^LAPTOP_USER=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); OS=$(grep -E "^LAPTOP_OS=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); PORT=$(grep -E "^TUNNEL_PORT=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s\nOS=%s\nPORT=%s\n" "$LU" "$OS" "$PORT"'
    $probe = @((SshX $probeCmd) -join "`n")
    $existingLu = ''; $existingOs = ''; $existingPort = ''
    foreach ($ln in ($probe -split "`r?`n")) {
        if ($ln -match '^LU=(.*)$') { $existingLu = $Matches[1].Trim() }
        elseif ($ln -match '^OS=(.*)$') { $existingOs = $Matches[1].Trim() }
        elseif ($ln -match '^PORT=(.*)$') { $existingPort = $Matches[1].Trim() }
    }
    if (-not $existingLu) { return $true }
    $mine = if ($script:LaptopUser) { $script:LaptopUser } elseif ($env:USERNAME) { $env:USERNAME } else { $env:USER }
    if ($existingLu -eq $mine) { return $true }

    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    $ssOk = $false
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || echo SS_UNKNOWN" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw; $ssOk = $true }
        else {
            Write-GitModeLog "SS:UNKNOWN port=$portDigits raw=$liveRaw - not clearing connect conf" 'WARN'
        }
    }
    # Only auto-clear when ss positively reports zero listeners (or no port in conf).
    if (-not $portDigits -or ($ssOk -and $live -eq 0)) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        [void](Invoke-SshXChecked -RemoteCmd 'rm -f ~/.claude-connect.conf' -Label 'CLEAR_CONNECT_CONF')
        return $true
    }
    if (-not $ssOk) {
        # Ambiguous: treat as possibly live and prompt below.
        Write-GitModeLog "FOREIGN_SESSION ss_ambiguous port=$portDigits - prompting" 'WARN'
    }

    $who = if ($RemoteUser) { $RemoteUser } else { '?' }
    $osTag = if ($existingOs) { " ($existingOs)" } else { '' }
    Warn ("Server account '{0}' is already used by laptop '{1}'{2} (tunnel active)." -f $who, $existingLu, $osTag)
    Warn ("Your laptop user is '{0}'. Taking over will disconnect them." -f $mine)

    $thisOs = 'windows'
    if ($existingOs -and $existingOs -ne $thisOs) {
        Warn ("OS mismatch ({0} vs {1}) - confirm this is your server account." -f $existingOs, $thisOs)
    }
    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    Continue and take over that session? [y/N]' -Tag 'FOREIGN_SESSION').Trim().ToLowerInvariant()
    } else { (Read-Host '    Continue and take over that session? [y/N]').Trim().ToLowerInvariant() }
    Write-GitModeLog "DECISION: foreign_session_takeover=$choice" 'WARN'

    if ($choice -ne 'y' -and $choice -ne 'yes') {
        Warn 'Aborted. Fix username with: connect.bat -Setup'
        return $false
    }
    return $true
}


function Invoke-SshXChecked {
    param(
        [Parameter(Mandatory)][string]$RemoteCmd,
        [string]$Label = 'SSHX'
    )
    $null = SshX $RemoteCmd 2>$null
    $ec = 0
    if ($null -ne $global:LASTEXITCODE) { $ec = [int]$global:LASTEXITCODE }
    if ($ec -ne 0) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("{0} fail exit={1}" -f $Label, $ec) 'WARN'
        } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("{0} fail exit={1}" -f $Label, $ec) 'WARN'
        } else {
            Write-Host ("  [!] {0} fail exit={1}" -f $Label, $ec) -ForegroundColor DarkYellow
        }
    }
    return $ec
}

function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Keep self-heal out of this frequently called configuration push hot path.
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    # Stage 5: refuse overwriting ACTIVE_MOUNT when another project is still mounted.
    # Perf: this used to pre-check via a separate `claude-mount check <currentAm>` SSH round
    # trip (~1.5s) before deciding $preferAm. That is pure duplicate work - the remoteBody
    # script shipped below (search ACTIVE_MOUNT_GUARD) already re-derives CUR_AM fresh from
    # the server conf file and applies the identical guard via a local `mountpoint -q` test
    # (no extra round trip), which is also more correct since it reads the server's live
    # conf instead of the client's possibly-stale $script:LastPushConfActive cache. Whatever
    # $preferAm we pass in, the remote script will still refuse to clobber a live other mount.
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    $sessionPort = Get-SessionTunnelPort
    # Never push TUNNEL_PORT empty/0 (NO_PORT / legacy 20000+UID fallback).
    if (-not $sessionPort -or [int]$sessionPort -le 0) {
        if (-not $script:ServerUidStr) {
            try {
                $script:ServerUidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
            } catch { $script:ServerUidStr = '' }
        }
        if ($script:ServerUidStr -and (Get-Command Get-TunnelPortUserBase -ErrorAction SilentlyContinue)) {
            $slotFb = 0
            if ($null -ne $script:TunnelSlot -and "$($script:TunnelSlot)" -match '^\d+$') {
                $slotFb = [int]$script:TunnelSlot
            }
            $sessionPort = [int](Get-TunnelPortUserBase -UidStr $script:ServerUidStr) + $slotFb
            Write-GitModeLog ("PUSH_CONF port_from_formula uid={0} slot={1} port={2}" -f $script:ServerUidStr, $slotFb, $sessionPort) 'INFO'
        }
    }
    if ($Port -and $script:Port -and ([int]$Port -ne [int]$script:Port)) {
        Write-GitModeLog ("PORT_SHADOW_DETECT bare={0} script={1} using={2}" -f $Port, $script:Port, $sessionPort) 'WARN'
    }
    # #17 strategy A: non-primary still pushes ACTIVE_MOUNT(+GIT_MODE); prefer not to
    # overwrite primary TUNNEL_PORT. Remote AM_ONLY body applies a liveness override
    # (port_takeover) when the published port is confirmed dead and this session's
    # port is confirmed listening — so a dead slot-0 cannot pin the fleet forever.
    $amOnly = $false
    if (Get-Command Test-IsPrimaryTunnelPublisher -ErrorAction SilentlyContinue) {
        if (-not (Test-IsPrimaryTunnelPublisher)) {
            $amOnly = $true
            Write-GitModeLog ("PUSH_CONF am_only slot={0} port={1} publish_port=0" -f ($env:CLAUDE_CONNECT_UI_SLOT), $sessionPort) 'INFO'
        }
    }
    # Dedupe identical pushes within a few seconds (startup called this twice).
    # Checked BEFORE the foreign-peer/hostkey safety probes below so a repeat push of
    # the same key skips their SSH round trips too (perf-only reorder; a cache-miss
    # still runs the exact same safety checks, in the exact same order, as before).
    $dedupeKey = "{0}|{1}|{2}|{3}|{4}|{5}" -f $LaptopUser, $sessionPort, $mode, $preferAm, $clearFlag, $(if ($amOnly) { "1" } else { "0" })
    if ($script:LastPushConfKey -eq $dedupeKey -and $script:LastPushConfAt -and
        ((Get-Date) - $script:LastPushConfAt).TotalSeconds -le 8) {
        Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" 'INFO'
        return
    }
    # Perf (2026-07-25, live evidence: "Server setup" burned ~4.1s here on every fresh connect):
    # both safety probes below only mean something when a process is ACTUALLY LISTENING on the
    # port. On a fresh connect our own reverse tunnel is not up yet, so the port is closed - a
    # closed port cannot host a foreign peer and has no host key to mismatch, so both checks are
    # guaranteed to say "fine". Test-TunnelHostKeyMismatch, however, still runs an ssh-keyscan
    # (Get-TunnelHostKeyFingerprint) that waits its full `timeout 4` against the dead loopback
    # port and returns empty. Gate BOTH checks on one cheap tcp-open probe: this REPLACES the
    # tcp probe that Test-TunnelPortIsForeignPeer would have run internally on the closed path
    # (so the common case adds no round trip) while removing the wasted keyscan entirely. The
    # open/reconnect path is unchanged in behavior (it just pays one extra ~1.4s tcp probe, and
    # only there both safety checks still run in full, in the same order as before).
    #
    # Session-fresh trust (2026-07-25, live: Prepare-ServerSessionParallel paid ~5s of
    # tcp+hostkey+banner right after Ensure-Tunnel already proved this port): when THIS
    # Connect's SessionBgTunnel just spawned/waited successfully for $sessionPort within
    # 30s (same stamp as ENSURE_TUNNEL recent_success), skip foreign/hostkey re-probes.
    # ForeignPeer clears TunnelBannerCache and re-runs nc+keyscan - pure waste on that path.
    # TTL matches LastTunnelSpawnSuccess recent_success window; miss falls through to full checks.
    $sessionTunnelFresh = $false
    if ($sessionPort -and $script:LastTunnelSpawnSuccessAt -and
        $script:LastTunnelSpawnSuccessPort -eq [int]$sessionPort -and
        $script:LastTunnelSpawnPid -and
        ((Get-Date) - $script:LastTunnelSpawnSuccessAt).TotalSeconds -lt 30) {
        $bgAlive = $false
        if ($script:SessionBgTunnel) {
            try { $bgAlive = -not $script:SessionBgTunnel.HasExited } catch { $bgAlive = $false }
            if ($bgAlive -and [int]$script:SessionBgTunnel.Id -eq [int]$script:LastTunnelSpawnPid) {
                $sessionTunnelFresh = $true
            }
        }
    }
    if ($sessionTunnelFresh) {
        Write-GitModeLog "PUSH_CONF safety_probes_skipped port=$sessionPort reason=session_tunnel_fresh" 'DEBUG'
    } else {
        $pushPortListening = $true
        if ($sessionPort -and (Get-Command Test-TunnelPortTcpOpen -ErrorAction SilentlyContinue)) {
            # Reuse the acquire batch verdict (issued ~1-2s earlier for this exact port) instead of a
            # fresh ssh probe; falls back to a live probe on a cache miss/expiry.
            $pushPortListening = [bool](Test-TunnelPortTcpOpen -TargetPort ([int]$sessionPort) -MaxCacheAgeMs 8000)
        }
        if ($pushPortListening) {
            # Never publish another peer's reverse port into ~/.claude-connect.conf.
            if ($sessionPort -and (Get-Command Test-TunnelPortIsForeignPeer -ErrorAction SilentlyContinue)) {
                if (Test-TunnelPortIsForeignPeer -TargetPort ([int]$sessionPort)) {
                    Write-GitModeLog "PUSH_CONF blocked: foreign_peer port=$sessionPort" 'ERROR'
                    return
                }
            }
            if ($sessionPort -and (Get-Command Test-TunnelHostKeyMismatch -ErrorAction SilentlyContinue)) {
                if (Test-TunnelHostKeyMismatch -TargetPort ([int]$sessionPort)) {
                    Write-GitModeLog "PUSH_CONF blocked: hostkey_mismatch port=$sessionPort" 'ERROR'
                    return
                }
            }
        } else {
            Write-GitModeLog "PUSH_CONF safety_probes_skipped port=$sessionPort reason=tcp_closed" 'DEBUG'
        }
    }
    # Escape for embedding inside a single-quoted bash assignment (avoid double quotes).
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$sessionPort" -replace "'", "'\''")
    $slotEsc = ("$($script:TunnelSlot)" -replace "'", "'\''")
    $hkEsc = ((Get-StoredLaptopHostKeyFingerprint) -replace "'", "'\''")
    $amOnlyFlag = if ($amOnly) { '1' } else { '0' }
    $publishPortLog = if ($amOnly) { '0' } else { "$sessionPort" }
    Write-GitModeLog "PUSH_CONF begin laptop_user=$LaptopUser port=$sessionPort slot=$($script:TunnelSlot) git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount am_only=$amOnlyFlag publish_port=$publishPortLog" 'INFO'
    # Windows OpenSSH eats nested double quotes in remote payloads (AM="" -> AM="; elif syntax error).
    # Ship remote body as base64 so ACTIVE_MOUNT always lands correctly and stays trackable.
    $remoteBody = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
LU='$lu'
PORT='$portEsc'
SLOT='$slotEsc'
MODE='$modeEsc'
HK='$hkEsc'
AM_ONLY='$amOnlyFlag'
CUR_AM=`$(grep -E '^ACTIVE_MOUNT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
CUR_PORT=`$(grep -E '^TUNNEL_PORT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
CUR_SLOT=`$(grep -E '^TUNNEL_SLOT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
if [ "`$CLEAR" = "1" ]; then
  AM=
elif [ -n "`$PREFER" ]; then
  if [ -n "`$CUR_AM" ] && [ "`$CUR_AM" != "`$PREFER" ] && mountpoint -q "`$HOME/mounts/`$CUR_AM" 2>/dev/null; then
    AM=`$CUR_AM
    printf 'ACTIVE_MOUNT_GUARD keep=%s prefer=%s reason=other_still_mounted\n' "`$CUR_AM" "`$PREFER"
  else
    AM=`$PREFER
  fi
else
  AM=`$CUR_AM
fi
if [ "`$AM_ONLY" = "1" ]; then
  if [ -n "`$CUR_PORT" ]; then
    # P1.3 liveness override: slot-index am_only must not permanently keep a dead
    # published port. Take over ONLY when CUR_PORT has no listener AND this
    # session's PORT is listening. If CUR_PORT is still up (multi-slot hard tests /
    # intentional dual Connect), keep it -- never race two live publishers.
    # Use single-quoted bash -c bodies (no double quotes) so ExpandString-based
    # live tests can re-interpolate this here-string template safely.
    CUR_LIVE=0
    if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'`$CUR_PORT 2>/dev/null; then
      CUR_LIVE=1
    fi
    OUR_LIVE=0
    if [ -n "`$PORT" ] && [ "`$PORT" != "0" ]; then
      if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'`$PORT 2>/dev/null; then
        OUR_LIVE=1
      fi
    fi
    if [ "`$CUR_LIVE" = "0" ] && [ "`$OUR_LIVE" = "1" ]; then
      PORT_OUT=`$PORT
      SLOT_OUT=`$SLOT
      PUBLISH_PORT=`$PORT
      printf 'PUSH_CONF port_takeover published_dead=%s session=%s slot=%s\n' "`$CUR_PORT" "`$PORT" "`$SLOT"
    else
      PORT_OUT=`$CUR_PORT
      SLOT_OUT=`$CUR_SLOT
      if [ -n "`$PORT" ] && [ "`$PORT" != "`$CUR_PORT" ]; then
        printf 'PUSH_CONF port_mismatch_keep session=%s server=%s cur_live=%s our_live=%s\n' "`$PORT" "`$CUR_PORT" "`$CUR_LIVE" "`$OUR_LIVE"
      fi
      PUBLISH_PORT=0
    fi
  else
    PORT_OUT=`$PORT
    SLOT_OUT=`$SLOT
    PUBLISH_PORT=0
  fi
else
  PORT_OUT=`$PORT
  SLOT_OUT=`$SLOT
  PUBLISH_PORT=`$PORT
fi
# Never wipe TUNNEL_PORT (empty/0 PORT_OUT -> laptop-exec NO_PORT / legacy 20000+UID).
if { [ -z "`$PORT_OUT" ] || [ "`$PORT_OUT" = "0" ]; } && [ -n "`$CUR_PORT" ] && [ "`$CUR_PORT" != "0" ]; then
  PORT_OUT=`$CUR_PORT
  SLOT_OUT=`$CUR_SLOT
  printf 'PUSH_CONF port_empty_recovered server=%s\n' "`$CUR_PORT"
fi
if [ -z "`$PORT_OUT" ] || [ "`$PORT_OUT" = "0" ]; then
  printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s am_only=%s publish_port=ABORT_EMPTY\n' "`$CLEAR" "`$PREFER" "`$AM" "`$AM_ONLY"
  exit 0
fi
mkdir -p "`$HOME/.local/bin"
printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nPORT=%s\nTUNNEL_SLOT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\nLAPTOP_HOSTKEY_FP=%s\n' "`$LU" "`$PORT_OUT" "`$PORT_OUT" "`$SLOT_OUT" "`$MODE" "`$AM" "`$HK" > "`$HOME/.claude-connect.conf"
chmod 600 "`$HOME/.claude-connect.conf" 2>/dev/null || true
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s am_only=%s publish_port=%s\n' "`$CLEAR" "`$PREFER" "`$AM" "`$AM_ONLY" "`$PUBLISH_PORT"
"@
    # Windows here-strings are CRLF; Linux bash then sees "set +e\r" -> "set: + : invalid option".
    $remoteBody = ($remoteBody -replace "`r`n", "`n") -replace "`r", "`n"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
    $remote = "echo $b64 | base64 -d | bash"
    # NoRetryOnTimeout: a hung PUSH_CONF must not burn two full SshX hard-kill budgets
    # (75s + 75s). Live 2026-08-02: deferred Server setup stuck with SSH_BEGIN PUSH_CONF
    # and no SSH_END while Wait-DeferredServerSetup polled forever.
    $pushOut = @(SshX $remote -NoRetryOnTimeout 2>$null)
    $pushExit = $global:LASTEXITCODE
    $pushRaw = ($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
    $pushLine = if ($null -eq $pushRaw -or "$pushRaw" -eq '') { '(no result line)' } else { ([string]$pushRaw -replace '\s+', ' ').Trim() }
    if (-not $pushLine) { $pushLine = '(no result line)' }
    $hasResult = [bool]($pushLine -match 'PUSH_CONF_RESULT')
    $pushScan = ((@($pushOut) | ForEach-Object { "$_" }) -join ' ') + ' ' + "$pushRaw" + ' ' + "$pushLine"
    # Exit 0 without PUSH_CONF_RESULT must NOT dedupe as success (silent false-ok).
    if ($pushExit -ne 0 -or -not $hasResult) {
        # Do not record dedupe on failure - allow immediate retry of the same prefer/clear key.
        Write-GitModeLog "PUSH_CONF fail exit=$pushExit out=$pushLine" 'ERROR'
        foreach ($sig in @('ABORT_EMPTY', 'port_empty_recovered', 'port_mismatch_keep', 'port_takeover')) {
            if ($pushScan -match [regex]::Escape($sig)) {
                Write-GitModeLog "PUSH_CONF signal=$sig out=$pushLine" 'WARN'
            }
        }
    } else {
        $script:LastPushConfKey = $dedupeKey
        $script:LastPushConfAt = Get-Date
        if ($pushLine -match 'active=(\S*)') {
            $script:LastPushConfActive = $Matches[1]
        }
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
        foreach ($sig in @('ABORT_EMPTY', 'port_empty_recovered', 'port_mismatch_keep', 'port_takeover')) {
            if ($pushScan -match [regex]::Escape($sig)) {
                Write-GitModeLog "PUSH_CONF signal=$sig out=$pushLine" 'WARN'
            }
        }
    }
}


function Read-RetryQuitKey {
    param([int]$TimeoutSec = 30)
    $interactiveBegin = Get-Date
    Write-GitModeLog "INTERACTIVE: retry_quit begin timeout_sec=$TimeoutSec" 'DEBUG'
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $rk = ''
    while ($rk -ne 'r' -and $rk -ne 'q') {
        if ([Console]::KeyAvailable) {
            $ki2 = [Console]::ReadKey($true)
            $kc2 = $ki2.KeyChar.ToString()
            $code2 = if ($kc2.Length -eq 1) { [int][char]$kc2[0] } else { 0 }
            $ascii2 = ($code2 -ge 32 -and $code2 -le 126)
            $letter2 = if ($ascii2) { $kc2.ToLowerInvariant() } else { '' }
            # VK fallback ONLY for null/control KeyChar - never Persian printable non-ASCII.
            $useVk2 = ($code2 -eq 0 -or ($code2 -gt 0 -and $code2 -lt 32))
            if ($letter2 -eq 'r' -or ($useVk2 -and $ki2.Key -eq [ConsoleKey]::R)) { $rk = 'r' }
            elseif ($letter2 -eq 'q' -or ($useVk2 -and $ki2.Key -eq [ConsoleKey]::Q)) { $rk = 'q' }
        } elseif ((Get-Date) -gt $deadline) {
            $rk = 'q'
            break
        } else {
            Start-Sleep -Milliseconds 200
        }
    }
    $elapsedMs = [int]((Get-Date) - $interactiveBegin).TotalMilliseconds
    Write-GitModeLog "INTERACTIVE: retry_quit end key=$rk elapsed_ms=$elapsedMs" 'DEBUG'
    return $rk
}

function Show-MountGitWarn {
    param([string]$MountOut)
    if ($MountOut -match '(?m)^warn: git hide failed') {
        $gitWarn = ($MountOut -split "`n" | Where-Object { $_ -match '^warn: git hide failed' } | Select-Object -First 1)
        if ($gitWarn) { Warn $gitWarn.Trim() }
    }
    if ($MountOut -match '(?m)^warn: laptop tunnel down') {
        $tw = ($MountOut -split "`n" | Where-Object { $_ -match '^warn: laptop tunnel' } | Select-Object -First 1)
        if ($tw) { Warn $tw.Trim() }
    }
}

function Clear-SessionMount {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = '',
        [switch]$StopEditor,
        [string]$Reason = ''
    )
    $skipEditor = -not $StopEditor
    $reasonPart = if ($Reason) { " reason=$Reason" } else { '' }
    Write-GitModeLog "CLEAR_MOUNT project=$ProjectId skip_editor=$([int]$skipEditor) editor=$EditorCmd path=$RemotePath$reasonPart" 'INFO'
    # Invalidate GIT_MODE=off session mount-ok TTL so auto_recovery cannot skipRemount a downed mount.
    $script:LastMountCheckOkAt = $null
    $script:LastMountCheckOkProject = $null
    if ($StopEditor -and $EditorCmd -and $Alias -and $RemotePath) {
        if (Get-Command Stop-RemoteEditor -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'CLEAR_MOUNT stopping editor (path-scoped)' 'DEBUG'
            Stop-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }
    }
    Clear-TunnelBannerCache
    if ($ProjectId) {
        $pidEsc = $ProjectId -replace "'", "'\\''"
        $downBegin = Get-Date
        Write-GitModeLog "CLEAR_MOUNT: down begin project=$ProjectId" 'INFO'
        [void](Invoke-SshXChecked -RemoteCmd "timeout 8 $CM down '$pidEsc' 2>/dev/null" -Label 'MOUNT_DOWN')
        $downMs = [int]((Get-Date) - $downBegin).TotalMilliseconds
        Write-GitModeLog "CLEAR_MOUNT: down end ms=$downMs project=$ProjectId" 'INFO'
    }
    if ($Port) {
        if (Get-Command Release-CursorProxyOwner -ErrorAction SilentlyContinue) { try { Release-CursorProxyOwner } catch {} }
        Push-ServerConnectConf -ClearActiveMount
    }
}

function Resolve-ServerScriptDir {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    # Prefer FULL server tree (claude-mount + laptop-exec) over published mac/
    # (mount-only). Otherwise Push-LaptopExecBundleIfChanged silently no-ops.
    try {
        $d = $ConnectScriptDir
        for ($i = 0; $i -lt 8; $i++) {
            $repoServer = [System.IO.Path]::Combine($d, 'scripts', 'server')
            $mountOk = Test-Path ([System.IO.Path]::Combine($repoServer, 'claude-mount.sh'))
            $leOk = Test-Path ([System.IO.Path]::Combine($repoServer, 'laptop-exec.sh'))
            if ($mountOk -and $leOk) { return $repoServer }
            $parent = Split-Path $d -Parent
            if (-not $parent -or $parent -eq $d) { break }
            $d = $parent
        }
    } catch { }
    foreach ($rel in @('server', '..\server', '..\..\server')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            $mountOk = Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))
            $leOk = Test-Path ([System.IO.Path]::Combine($d, 'laptop-exec.sh'))
            if ($mountOk -and $leOk) { return $d }
        } catch { }
    }
    # Mount-only fallback (Desktop Claude-Connect\mac) — LE push may no-op.
    foreach ($rel in @('..\mac', 'mac', '..\..\mac')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))) { return $d }
        } catch { }
    }
    try {
        $d = $ConnectScriptDir
        for ($i = 0; $i -lt 8; $i++) {
            $repoServer = [System.IO.Path]::Combine($d, 'scripts', 'server')
            if (Test-Path ([System.IO.Path]::Combine($repoServer, 'claude-mount.sh'))) { return $repoServer }
            $parent = Split-Path $d -Parent
            if (-not $parent -or $parent -eq $d) { break }
            $d = $parent
        }
    } catch { }
    return $null
}

function Push-RemoteUserFileIfChanged {
    param(
        [Parameter(Mandatory)][string]$LocalSrc,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Alias,
        [switch]$Executable
    )
    if (-not (Test-Path $LocalSrc)) { return }
    $localHash = (Get-FileHash -Algorithm SHA256 -Path $LocalSrc).Hash
    # Quoted '~' does not expand on remote - use $HOME for ssh cmds; keep ~/ for scp.
    $rpath = $RemotePath
    if ($RemotePath.StartsWith('~/')) { $rpath = '$HOME/' + $RemotePath.Substring(2) }
    elseif ($RemotePath -eq '~') { $rpath = '$HOME' }
    $remoteHash = ((SshX "sha256sum $rpath 2>/dev/null | awk '{print `$1}'") -join '').Trim()
    if ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower())) { return }
    [void](Invoke-SshXChecked -RemoteCmd ('mkdir -p "$(dirname ' + $rpath + ')"') -Label 'PUSH_MKDIR')
    # These targets (laptop-exec, claude-self-heal, claude-automount, ...) can be
    # live-executed concurrently - scp to a .new sibling, then mv atomically into
    # place so a process already running the old copy never reads a torn file.
    $rNewPath = "$RemotePath.new"
    $rpathNew = "$rpath.new"
    scp -o BatchMode=yes -o ConnectTimeout=20 -q $LocalSrc "${Alias}:$rNewPath" 2>$null
    if ($LASTEXITCODE -eq 0) {
        if ($Executable) {
            [void](Invoke-SshXChecked -RemoteCmd ("chmod +x $rpathNew && mv -f $rpathNew $rpath") -Label 'PUSH_CHMOD')
        } else {
            [void](Invoke-SshXChecked -RemoteCmd ("mv -f $rpathNew $rpath") -Label 'PUSH_MOVE')
        }
    }
}

function Push-LaptopExecBundleIfChanged {
    param(
        [Parameter(Mandatory)][string]$ServerDir,
        [Parameter(Mandatory)][string]$Alias
    )
    if (-not (Test-Path ([System.IO.Path]::Combine($ServerDir, 'laptop-exec.sh')))) {
        Write-Host "  warn  LE push skipped: no laptop-exec.sh under $ServerDir (mount-only dir; reconnect from repo or run sudo claude-server deploy-laptop-exec)" -ForegroundColor Yellow
        return
    }
    $pairs = @(
        @{ Local = 'laptop-exec.sh'; Remote = '~/.local/bin/laptop-exec'; Exec = $true },
        @{ Local = 'laptop-exec-setup.sh'; Remote = '~/.local/bin/laptop-exec-setup'; Exec = $true },
        @{ Local = 'claude-self-heal.sh'; Remote = '~/.local/bin/claude-self-heal'; Exec = $true },
        @{ Local = 'claude-automount.sh'; Remote = '~/.local/bin/claude-automount'; Exec = $true },
        @{ Local = 'cursor-rules/laptop-exec.mdc'; Remote = '~/.cursor/rules/laptop-exec.mdc'; Exec = $false },
        @{ Local = 'skills/laptop-exec/SKILL.md'; Remote = '~/.cursor/skills/laptop-exec/SKILL.md'; Exec = $false },
        @{ Local = 'cursor-hooks/laptop-exec-guard.sh'; Remote = '~/.cursor/hooks/laptop-exec-guard.sh'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-guard-wrap.sh'; Remote = '~/.cursor/hooks/laptop-exec-guard-wrap.sh'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-shell-scan.py'; Remote = '~/.cursor/hooks/laptop-exec-shell-scan.py'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-audit-log.sh'; Remote = '~/.cursor/hooks/laptop-exec-audit-log.sh'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-session.sh'; Remote = '~/.cursor/hooks/laptop-exec-session.sh'; Exec = $true }
    )
    foreach ($p in $pairs) {
        $src = [System.IO.Path]::Combine($ServerDir, $p.Local)
        Push-RemoteUserFileIfChanged -LocalSrc $src -RemotePath $p.Remote -Alias $Alias -Executable:$p.Exec
    }
    # Windows scp can leave CRLF - strip on server for Win+Mac users alike
    SshX "sed -i 's/\r$//' ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.local/bin/claude-self-heal ~/.local/bin/claude-automount ~/.local/bin/claude-mount ~/.cursor/hooks/laptop-exec-*.sh ~/.cursor/hooks/laptop-exec-shell-scan.py 2>/dev/null; chmod +x ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.local/bin/claude-self-heal ~/.local/bin/claude-automount ~/.cursor/hooks/laptop-exec-*.sh 2>/dev/null; true" 2>$null | Out-Null
    if (Test-Path ([System.IO.Path]::Combine($ServerDir, 'laptop-exec-setup.sh'))) {
        SshX '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>$null | Out-Null
    }
    # Self-heal for both Windows and Mac laptop sessions (runs on Linux server)
    SshX '$HOME/.local/bin/claude-self-heal --quiet 2>/dev/null; /usr/local/bin/claude-self-heal --quiet 2>/dev/null; true' 2>$null | Out-Null
}

function Push-ClaudeServerScripts {
    param(
        [Parameter(Mandatory)][string]$ConnectScriptDir,
        [Parameter(Mandatory)][string]$Alias
    )
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if (-not $dir) { return $false }
    $src = [System.IO.Path]::Combine($dir, 'claude-mount.sh')
    $gitSrc = [System.IO.Path]::Combine($dir, 'claude-git-setup.sh')
    $pushOk = $true
    $gitPushed = $false
    if (Test-Path $src) {
        Push-ClaudeMountIfChanged -Src $src -Alias $Alias
    }
    if (Test-Path $gitSrc) {
        $localGit = (Get-FileHash -Algorithm SHA256 -Path $gitSrc).Hash
        $remoteGit = ((SshX "sha256sum ~/.local/bin/claude-git-setup 2>/dev/null | awk '{print `$1}'") -join '').Trim()
        if (-not ($localGit -and $remoteGit -and ($localGit.ToLower() -eq $remoteGit.ToLower()))) {
            scp -o BatchMode=yes -o ConnectTimeout=30 -q $gitSrc "${Alias}:~/.local/bin/claude-git-setup.new" 2>$null
            if ($LASTEXITCODE -ne 0) { $pushOk = $false; $script:pendingFixes += 'claude-git-setup push failed' }
            else { $gitPushed = $true }
        }
    }
    $chmodCmd = @()
    if (Test-Path $src) { $chmodCmd += "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc" }
    if ($gitPushed) { $chmodCmd += 'chmod +x ~/.local/bin/claude-git-setup.new && mv -f ~/.local/bin/claude-git-setup.new ~/.local/bin/claude-git-setup' }
    if ($chmodCmd.Count -gt 0) { [void](Invoke-SshXChecked -RemoteCmd ($chmodCmd -join '; ') -Label 'PUSH_CHMOD_MOUNT') }
    Push-LaptopExecBundleIfChanged -ServerDir $dir -Alias $Alias
    return $pushOk
}

function Test-MountSuccess {
    param(
        [string]$MountOut,
        [int]$ExitCode = 0
    )
    if ($MountOut -match 'error:|No tunnel|not configured|unbound variable') { return $false }
    if ($MountOut -cmatch 'FAILED') { return $false }
    if ($ExitCode -eq 0) { return $true }
    if ($MountOut -match 'already mounted:') { return $true }
    return $false
}

function Invoke-MountProject {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$ConnectScriptDir,
        [Parameter(Mandatory)][string]$Alias,
        [switch]$TrustedTunnel,
        [Nullable[bool]]$CheckOkHint = $null
    )
    $trusted = if ($TrustedTunnel) { 'CLAUDE_TRUSTED_TUNNEL=1 ' } else { '' }
    # WS4: only assert BANNER_OK when this client already ran its own successful banner probe
    # this session (Test-TunnelUp) AND the caller trusts the tunnel - never on its own.
    $bannerOk = if ($TrustedTunnel -and $script:TunnelBannerCacheUp) { 'CLAUDE_TUNNEL_BANNER_OK=1 ' } else { '' }
    # DEBUG c46ba1: opt-in server-side perf breakdown (PERF_HIDE_MS / PERF_SSHFS_MS) so a slow
    # `claude-mount up` can be split into git-hide-over-reverse-SSH vs the sshfs mount itself.
    $perfEnv = if ((Get-Command Test-ConnectPerfEnabled -ErrorAction SilentlyContinue) -and (Test-ConnectPerfEnabled)) { 'CLAUDE_CONNECT_PERF_LOG=1 ' } else { '' }
    Write-GitModeLog "MOUNT_UP begin project=$ProjectId trusted=$TrustedTunnel banner_ok=$([bool]$bannerOk) check_hint=$CheckOkHint" 'DEBUG'
    # A caller (e.g. Invoke-RecoverIfNeeded) may already have run the `check` probe this same
    # iteration - reuse that result to skip our own redundant SSH round-trip. This NEVER skips
    # the `$CM up` call itself below, because git hide/.claude-stub application must always run.
    if ($null -ne $CheckOkHint) {
        Write-GitModeLog "MOUNT_UP check_reuse project=$ProjectId hint=$CheckOkHint reason=recover_hint_same_iter" 'DEBUG'
    } elseif ((Get-GitMode) -eq 'off' -and (Test-ProjectMountHealthy -ProjectId $ProjectId)) {
        Write-GitModeLog "MOUNT_UP off_mode_apply project=$ProjectId reason=check_ok_still_up" 'DEBUG'
    }
    $swMount = [System.Diagnostics.Stopwatch]::StartNew()
    $mountOut = (SshX "${perfEnv}${trusted}${bannerOk}$CM up '$ProjectId' 2>&1") | Out-String
    $exitCode = $LASTEXITCODE
    $swMount.Stop()
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark 'mount_ssh_up' -Ms $swMount.ElapsedMilliseconds -Extra "attempt=1 exit=$exitCode"
    }
    if ($mountOut -match 'PERF_HIDE_MS=(\d+)') {
        Write-ConnectPerfLog -Mark 'mount_hide' -Ms ([int]$Matches[1]) -Extra 'attempt=1 source=claude-mount'
    }
    if ($mountOut -match 'PERF_SSHFS_MS=(\d+)') {
        Write-ConnectPerfLog -Mark 'mount_sshfs' -Ms ([int]$Matches[1]) -Extra 'attempt=1 source=claude-mount'
    }
    Write-GitModeLog "MOUNT_UP first exit=$exitCode out=$($mountOut.Trim() -replace '\s+',' ')" 'DEBUG'
    if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
        Write-GitModeLog "MOUNT_UP ok=1 project=$ProjectId" 'INFO'
        if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
            Write-ConnectPerfLog -Mark 'mount_total' -Ms $swMount.ElapsedMilliseconds -Extra 'path=ok attempt=1'
        }
        return @{ Ok = $true; Out = $mountOut }
    }
    if ($mountOut -match 'unbound variable|syntax error near unexpected') {
        Write-Host '      -> server mount script outdated, pushing update...' -ForegroundColor DarkGray
        if (Push-ClaudeServerScripts -ConnectScriptDir $ConnectScriptDir -Alias $Alias) {
            $swRetry = [System.Diagnostics.Stopwatch]::StartNew()
            $mountOut = (SshX "${perfEnv}${trusted}${bannerOk}$CM up '$ProjectId' 2>&1") | Out-String
            $exitCode = $LASTEXITCODE
            $swRetry.Stop()
            if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                Write-ConnectPerfLog -Mark 'mount_ssh_up' -Ms $swRetry.ElapsedMilliseconds -Extra "attempt=2 exit=$exitCode"
            }
            if ($mountOut -match 'PERF_HIDE_MS=(\d+)') {
                Write-ConnectPerfLog -Mark 'mount_hide' -Ms ([int]$Matches[1]) -Extra 'attempt=2 source=claude-mount'
            }
            if ($mountOut -match 'PERF_SSHFS_MS=(\d+)') {
                Write-ConnectPerfLog -Mark 'mount_sshfs' -Ms ([int]$Matches[1]) -Extra 'attempt=2 source=claude-mount'
            }
            if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
                if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                    Write-ConnectPerfLog -Mark 'mount_total' -Ms ($swMount.ElapsedMilliseconds + $swRetry.ElapsedMilliseconds) -Extra 'path=ok attempt=2'
                }
                return @{ Ok = $true; Out = $mountOut }
            }
        }
    }
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark 'mount_total' -Ms $swMount.ElapsedMilliseconds -Extra 'path=fail'
    }
    return @{ Ok = $false; Out = $mountOut }
}

function Remount-ProjectGit {
    param([string]$ProjectId)
    if (-not $ProjectId) { return $false }
    Write-Host ''
    Write-Host '    Remounting with git mode...' -ForegroundColor Cyan
    [void](Invoke-SshXChecked -RemoteCmd "$CM down '$ProjectId'" -Label 'MOUNT_DOWN')
    Write-Host '      -> recovering stale mounts...' -ForegroundColor DarkGray
    SshX "$CM recover" 2>$null | Out-Null
    if (-not (Test-Tunnel)) {
        Warn 'Tunnel dropped during remount - press R to reconnect'
        return $false
    }
    $mountOut = (SshX "CLAUDE_TRUSTED_TUNNEL=1 $CM up '$ProjectId' 2>&1") | Out-String
    Show-MountGitWarn $mountOut
    $mountOk = Test-MountSuccess -MountOut $mountOut -ExitCode $LASTEXITCODE
    if (-not $mountOk) {
        Warn ($mountOut.Trim())
        return $false
    }
    $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '' -replace '^mounted:\s*', '')
    $cleanOut = (($cleanOut -split '\r?\n')[0]).Trim()
    if ($cleanOut -and $cleanOut -notmatch '^warn:') { Write-Host "      -> $cleanOut" -ForegroundColor DarkGray }
    Write-Host "    Git mode: $(Get-GitMode) applied." -ForegroundColor Green
    Write-Host ''
    return $true
}

function Configure-GitMode {
    Write-Host ''
    Write-Host '    Git on server (SSHFS)' -ForegroundColor White
    Write-Host ''
    Write-Host '    HIDE/SLOW are disabled site-wide. Forced OFF (no .git rename).' -ForegroundColor Yellow
    Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'off' -Encoding ASCII | Out-Null
    Write-GitModeLog 'DECISION: git_mode=off (forced; hide/server disabled)' 'INFO'
    if ($Port) {
        $am = if ($script:ActiveProjectId) { $script:ActiveProjectId } else { '' }
        Push-ServerConnectConf -ActiveMount $am
    }
    Write-Host ''
    Write-Host '    Saved: git OFF.' -ForegroundColor Green
    if ($script:ActiveProjectId) {
        Push-ServerConnectConf -ActiveMount $script:ActiveProjectId
        Remount-ProjectGit -ProjectId $script:ActiveProjectId | Out-Null
    } else {
        Write-Host '    Reconnect to apply on first mount.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

