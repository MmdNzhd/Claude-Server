#Requires -Version 5.1
# Complete hygiene coverage: interactive UX, Close-Cursor window targeting,
# marker round-trip, empty ops, Mac parity contracts, docs/version lockstep.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Connect hygiene COMPLETE ===' -ForegroundColor Cyan

$git = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$el = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$mac = Get-Content (Get-ClientFile 'mac/connect.sh') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$uiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw
$docs = Get-Content (Join-Path $script:RepoRoot 'docs\client-connect.md') -Raw
$verWin = (Get-Content (Get-ClientFile 'windows/connect-version.txt') -Raw).Trim()
$verMac = (Get-Content (Get-ClientFile 'mac/connect-version.txt') -Raw).Trim()
$winPs = Get-Content (Get-ClientFile 'windows/connect.ps1') -Raw

# --- Docs / version / designer out-of-scope ---
Assert ($docs -match '`H`') 'docs document H hygiene'
Assert ($docs -match 'no menu path|project-menu') 'docs document git menu removal'
Assert ($verWin -eq $verMac) "Win/Mac version.txt lockstep ($verWin)"
Assert ($winPs -match [regex]::Escape("ConnectVersion = '$verWin'")) 'connect.ps1 matches version.txt'
Assert ($mac -match [regex]::Escape("CONNECT_VERSION='$verMac'")) 'mac connect.sh matches version.txt'
$des = Get-Content (Get-ClientFile 'users/designer/connect.ps1') -Raw
Assert ($des -match 'G = git mode') 'designer still has G (out of scope)'
Assert ($des -notmatch 'Show-ConnectHygieneInteractive|H hygiene') 'designer does not ship H hygiene'

# --- Mac parity contracts ---
Assert ($gmSh -match 'show_connect_hygiene_interactive') 'Mac has show_connect_hygiene_interactive'
Assert ($gmSh -match 'remove_local_orphan_tunnel') 'Mac soft uses remove_local_orphan_tunnel'
Assert ($gmSh -match 'cursor-server-reaper') 'Mac soft fail-open reaper'
Assert ($gmSh -match 'HYGIENE_SIBLING_STOP connect_ui') 'Mac sibling stops Connect UI from marker'
Assert ($gmSh -match '_close_cursor_project_windows_mac') 'Mac sibling closes Cursor window helper'
Assert ($gmSh -match 'protect_current') 'Mac Cursor close skips protect_current'
Assert ($gmSh -match 'mark_pid" != "\$\$"') 'Mac never kills self $$ as Connect UI'
Assert ($gmSh -match 'Re-scan siblings after soft') 'Mac re-scans siblings after soft (Win parity)'
Assert ($mac -match 'write_connect_session_slot_marker') 'Mac session writes slot marker'
Assert ($mac -match 'clear_connect_session_slot_marker') 'Mac disconnect clears slot marker'
Assert ($uiSh -match 'H = hygiene') 'Mac footer H hygiene'
Assert ($uiSh -notmatch 'G = git mode') 'Mac footer no G git'

# --- Marker round-trip (real Write/Get, live ping PID) ---
Write-Host ''
Write-Host '--- Marker round-trip ---' -ForegroundColor DarkCyan
foreach ($n in @('Write-GitModeLog','Get-ConnectSessionSlotMarkerDir','Get-ConnectSessionSlotMarkerPath','Write-ConnectSessionSlotMarker','Clear-ConnectSessionSlotMarker','Get-ConnectSessionSlotMarkers')) {
    . ([scriptblock]::Create((Get-FunctionSource -Content $git -Name $n)))
}
$script:CfgDir = Join-Path $env:TEMP ("cc-hyg-complete-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $script:CfgDir | Out-Null
function Get-ConnectSessionSlotMarkerDir { return [string]$script:CfgDir }
$ping = $null
try {
    $ping = Start-Process -FilePath ping -ArgumentList '-t','127.0.0.1' -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 250
    Write-ConnectSessionSlotMarker -Slot 3 -Port 20003 -ProjectId 'RoundTrip' -RemotePath 'D:\work\RoundTrip' -ProcessId $ping.Id
    $marks = @(Get-ConnectSessionSlotMarkers)
    Assert ($marks.Count -eq 1) "marker round-trip count=1 (got $($marks.Count))"
    Assert ($marks[0].ProjectId -eq 'RoundTrip') 'marker ProjectId RoundTrip'
    Assert ($marks[0].Port -eq 20003) 'marker Port 20003'
    Assert ($marks[0].Pid -eq $ping.Id) "marker Pid matches ping $($ping.Id)"
    Clear-ConnectSessionSlotMarker -Slot 3
    Assert (@(Get-ConnectSessionSlotMarkers).Count -eq 0) 'Clear-ConnectSessionSlotMarker removes marker'
} finally {
    if ($ping) { try { Stop-Process -Id $ping.Id -Force -ErrorAction SilentlyContinue } catch { } }
    Remove-Item -LiteralPath $script:CfgDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Empty Soft/Sibling are no-ops (no throws) ---
Write-Host ''
Write-Host '--- Empty ops ---' -ForegroundColor DarkCyan
$script:orphanPorts = New-Object System.Collections.Generic.List[int]
$script:tunnelStops = New-Object System.Collections.Generic.List[string]
$script:uiStops = New-Object System.Collections.Generic.List[int]
$script:cursorCloses = New-Object System.Collections.Generic.List[string]
function Write-GitModeLog { param($Message,$Level='INFO') }
function Get-LocalTunnelSshPids { param([int]$TargetPort); [void]$script:softPidProbes.Add([int]$TargetPort); return @() }
function Get-ConnectKeepTunnelMarkers { return @() }
function Remove-LocalOrphanTunnel {
    param([int]$TargetPort,$CurrentBgTunnel=$null,[int[]]$ProtectedProcessIds=@())
    [void]$script:orphanPorts.Add([int]$TargetPort)
    return $true
}
function Stop-TunnelProcessWithExitLog { param([int]$ProcessId,[string]$Reason='') ; [void]$script:tunnelStops.Add(('{0}:{1}' -f $ProcessId, $Reason)) }
function Close-CursorProjectWindows { param([string]$ProjectRootName,[string]$ProtectRootName='',[string]$Alias='claude-server'); [void]$script:cursorCloses.Add($ProjectRootName); return 0 }
function SshX { param([Parameter(ValueFromRemainingArguments=$true)]$Args); return 'MUX_DEAD_REMOVED=0' }
function Stop-Process { [CmdletBinding()] param([int]$Id,[switch]$Force); [void]$script:uiStops.Add([int]$Id) }
. ([scriptblock]::Create((Get-FunctionSource -Content $git -Name 'Invoke-ConnectHygieneClean')))
$empty = [pscustomobject]@{
    PortBase=20000; CurrentPid=[int]$PID; CurrentTunnelPid=0; ProtectRootName='Cur'
    ProtectRemotePath=''; Markers=@(); KeepMarkers=@(); Tunnels=@(); OrphanTunnelPids=@(); Siblings=@()
    SoftTargetCount=0; SiblingCount=0; Server=[pscustomobject]@{Ok=$false}
}
$script:orphanPorts.Clear()
$script:softPidProbes = New-Object System.Collections.Generic.List[int]
$null = Invoke-ConnectHygieneClean -Mode Soft -Report $empty
Assert ($script:softPidProbes.Count -ge 10) 'empty Soft still probes all 10 UID ports'
Assert ($script:orphanPorts.Count -eq 0) 'empty Soft no Remove when no local -R'
Assert ($script:tunnelStops.Count -eq 0 -and $script:uiStops.Count -eq 0 -and $script:cursorCloses.Count -eq 0) 'empty Soft no sibling side effects'
$script:orphanPorts.Clear(); $script:tunnelStops.Clear(); $script:uiStops.Clear(); $script:cursorCloses.Clear()
$null = Invoke-ConnectHygieneClean -Mode Sibling -Report $empty
Assert ($script:orphanPorts.Count -eq 0 -and $script:tunnelStops.Count -eq 0 -and $script:uiStops.Count -eq 0 -and $script:cursorCloses.Count -eq 0) 'empty Sibling is a pure no-op'

# --- Interactive: cancel soft / soft-only / soft+sibling ---
Write-Host ''
Write-Host '--- Interactive UX ---' -ForegroundColor DarkCyan
$script:softCalls = 0; $script:sibCalls = 0; $script:deepCalls = 0; $script:reportCalls = 0
$script:answers = [System.Collections.Generic.Queue[string]]::new()
function Read-Host { param([string]$Prompt) if ($script:answers.Count -eq 0) { return 'n' }; return $script:answers.Dequeue() }
function Get-ConnectHygieneReport {
    param([string]$UidStr='',[string]$ProtectRemotePath='',[string]$ProtectProjectId='',[switch]$SkipServer)
    $script:reportCalls++
    if ($SkipServer -and $script:softCalls -ge 1) {
        return [pscustomobject]@{ SoftTargetCount=0; SiblingCount=1; KeepMarkers=@(); Tunnels=@(); Server=[pscustomobject]@{Ok=$false;Detail='skip'}; Siblings=@([pscustomobject]@{}) }
    }
    return [pscustomobject]@{
        SoftTargetCount=1; SiblingCount=1; KeepMarkers=@()
        Tunnels=@([pscustomobject]@{Class='orphan';Port=20002;TunnelPid=1;ConnectUiPid=0;ProjectId=''})
        Server=[pscustomobject]@{Ok=$true;SftpCount=0;ListenPorts=@(20000)}
        Siblings=@([pscustomobject]@{})
    }
}
function Invoke-ConnectHygieneClean {
    param([string]$Mode,$Report,[string]$ProtectRemotePath='',[string]$ProtectProjectId='')
    if ($Mode -eq 'Soft') { $script:softCalls++; return [pscustomobject]@{OrphansKilled=1;MuxCleaned=0} }
    $script:sibCalls++
    return [pscustomobject]@{SiblingTunnels=1;SiblingConnects=1;CursorWindows=1}
}
function Invoke-ConnectHygieneDeepClean {
    param($Report,[string]$ProtectRemotePath='',[string]$ProtectProjectId='',[string]$Alias='claude-server')
    $script:deepCalls++
    return [pscustomobject]@{SiblingTunnels=0;SiblingConnects=0;CursorWindows=0;KeepCleared=0;OrphansKilled=0}
}
. ([scriptblock]::Create((Get-FunctionSource -Content $git -Name 'Show-ConnectHygieneInteractive')))

$script:answers.Clear(); $script:answers.Enqueue('n')
$script:softCalls=0; $script:sibCalls=0; $script:deepCalls=0; $script:reportCalls=0
Show-ConnectHygieneInteractive -UidStr '1000' -ProtectRemotePath 'D:\work\Cur' -ProtectProjectId 'Cur' | Out-Null
Assert ($script:softCalls -eq 0 -and $script:sibCalls -eq 0 -and $script:deepCalls -eq 0) 'interactive N on soft cancels (no Soft/Sibling/Deep clean)'

# Soft Y + Deep N + Sibling N
$script:answers.Clear(); $script:answers.Enqueue('y'); $script:answers.Enqueue('n'); $script:answers.Enqueue('n')
$script:softCalls=0; $script:sibCalls=0; $script:deepCalls=0
Show-ConnectHygieneInteractive -UidStr '1000' -ProtectRemotePath 'D:\work\Cur' -ProtectProjectId 'Cur' | Out-Null
Assert ($script:softCalls -eq 1 -and $script:sibCalls -eq 0 -and $script:deepCalls -eq 0) 'interactive Y soft + N deep + N sibling runs Soft only'

# Soft YES + Deep N + Sibling YES
$script:answers.Clear(); $script:answers.Enqueue('yes'); $script:answers.Enqueue('n'); $script:answers.Enqueue('YES')
$script:softCalls=0; $script:sibCalls=0; $script:deepCalls=0
Show-ConnectHygieneInteractive -UidStr '1000' -ProtectRemotePath 'D:\work\Cur' -ProtectProjectId 'Cur' | Out-Null
Assert ($script:softCalls -eq 1 -and $script:sibCalls -eq 1 -and $script:deepCalls -eq 0) 'interactive YES soft + N deep + YES sibling runs Soft then Sibling'
Assert ($script:reportCalls -ge 2) 'interactive re-scans after soft (SkipServer path)'

# Soft Y + Deep Y short-circuits Sibling
$script:answers.Clear(); $script:answers.Enqueue('y'); $script:answers.Enqueue('y')
$script:softCalls=0; $script:sibCalls=0; $script:deepCalls=0
Show-ConnectHygieneInteractive -UidStr '1000' -ProtectRemotePath 'D:\work\Cur' -ProtectProjectId 'Cur' | Out-Null
Assert ($script:softCalls -eq 1 -and $script:deepCalls -eq 1 -and $script:sibCalls -eq 0) 'interactive Deep Y runs Deep and skips Sibling prompt'

# Nothing to clean
function Get-ConnectHygieneReport {
    param([string]$UidStr='',[string]$ProtectRemotePath='',[string]$ProtectProjectId='',[switch]$SkipServer)
    $script:reportCalls++
    return [pscustomobject]@{ SoftTargetCount=0; SiblingCount=0; Tunnels=@(); Server=[pscustomobject]@{Ok=$false;Detail='skip'}; Siblings=@() }
}
$script:softCalls=0; $script:sibCalls=0; $script:answers.Clear()
Show-ConnectHygieneInteractive -UidStr '1000' | Out-Null
Assert ($script:softCalls -eq 0 -and $script:sibCalls -eq 0) 'interactive nothing-to-clean skips prompts/clean'

# --- Close-CursorProjectWindows window targeting ---
Write-Host ''
Write-Host '--- Close-Cursor window targeting ---' -ForegroundColor DarkCyan
$script:posted = New-Object System.Collections.Generic.List[string]
function Write-EditorLaunchLog { param($Message,$Level='INFO') }
function Initialize-Win32WindowClose { }
function Get-CursorWindowTitleTag { return 'Claude Server Smart' }
function Get-CursorMainProfileProcesses { return @([pscustomobject]@{ ProcessId = 424242 }) }
function Get-CursorMainPersonalProcesses { throw 'Close-Cursor must never call personal process enum' }
function Get-ProcessTopLevelWindows {
    param([int]$ProcessId)
    return @(
        [pscustomobject]@{ Hwnd = 11; Title = '[Claude Server Smart] SiblingProj' }
        [pscustomobject]@{ Hwnd = 12; Title = '[Claude Server Smart] CurrentProj' }
        [pscustomobject]@{ Hwnd = 13; Title = '[Claude Server Smart] OtherProj' }
        [pscustomobject]@{ Hwnd = 14; Title = 'personal unrelated' }
    )
}
if (-not ('ClaudeConnectWin32Close' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
public static class ClaudeConnectWin32Close {
    public const int WM_CLOSE = 0x10;
    public static int PostCount = 0;
    public static string LastHwnd = "";
    public static bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam) {
        PostCount++;
        LastHwnd = hWnd.ToString();
        return true;
    }
}
'@
}
# Load title matcher + Close-Cursor from editor-launch
foreach ($n in @('Test-CursorWindowTitleMatchesProject','Close-CursorProjectWindows')) {
    $src = Get-FunctionSource -Content $el -Name $n
    Assert ($src.Length -gt 40) "extract $n"
    . ([scriptblock]::Create($src))
}
# Wrap PostMessage counting via redefining Close to use our type (already loaded)
[ClaudeConnectWin32Close]::PostCount = 0
$nClose = Close-CursorProjectWindows -ProjectRootName 'SiblingProj' -ProtectRootName 'CurrentProj' -Alias 'claude-server'
Assert ($nClose -eq 1) "Close-Cursor closes only SiblingProj (got $nClose)"
Assert ([ClaudeConnectWin32Close]::PostCount -eq 1) 'Close-Cursor posted exactly one WM_CLOSE'
Assert ([ClaudeConnectWin32Close]::LastHwnd -eq '11') 'Close-Cursor targeted SiblingProj hwnd=11'
$nSkip = Close-CursorProjectWindows -ProjectRootName 'CurrentProj' -ProtectRootName 'CurrentProj'
Assert ($nSkip -eq 0 -and [ClaudeConnectWin32Close]::PostCount -eq 1) 'Close-Cursor equals_protect returns 0 without extra posts'
$before = [ClaudeConnectWin32Close]::PostCount
$nOther = Close-CursorProjectWindows -ProjectRootName 'MissingProj' -ProtectRootName 'CurrentProj'
Assert ($nOther -eq 0 -and [ClaudeConnectWin32Close]::PostCount -eq $before) 'Close-Cursor no-match does not process-kill (post count unchanged)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
