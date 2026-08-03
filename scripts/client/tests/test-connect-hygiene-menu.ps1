#Requires -Version 5.1
# Contracts + HARD runtime: Soft never targets siblings; Sibling targets tunnel+UI+window only.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}
function Get-FunctionSourceRegex {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Connect hygiene menu contracts ===' -ForegroundColor Cyan

$git = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$el = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$win = Get-Content (Get-ClientFile 'windows/connect.ps1') -Raw
$uiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw
$mac = Get-Content (Get-ClientFile 'mac/connect.sh') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$bat = Get-Content (Get-ClientFile 'windows/connect.bat') -Raw

$report = Get-FunctionSourceRegex $git 'Get-ConnectHygieneReport'
$clean2 = Get-FunctionSourceRegex $git 'Invoke-ConnectHygieneClean'
$show = Get-FunctionSourceRegex $git 'Show-ConnectHygieneInteractive'
$closeWin = Get-FunctionSourceRegex $el 'Close-CursorProjectWindows'

Assert ($report.Length -gt 80) 'Get-ConnectHygieneReport exists'
Assert ($clean2.Length -gt 80) 'Invoke-ConnectHygieneClean exists'
Assert ($show.Length -gt 40) 'Show-ConnectHygieneInteractive exists'
Assert ($report -match 'HYGIENE_SCAN') 'report logs HYGIENE_SCAN'
Assert ($clean2 -match "ValidateSet\('Soft','Sibling'\)") 'clean modes Soft|Sibling'
Assert ($clean2 -match 'Remove-LocalOrphanTunnel') 'Soft path uses Remove-LocalOrphanTunnel'
Assert ($clean2 -match 'hygiene_sibling') 'Sibling stops tunnels with hygiene_sibling'
Assert ($clean2 -match 'Close-CursorProjectWindows') 'Sibling closes project Cursor windows'
Assert ($clean2 -match 'Stop-Process -Id \$uiPid') 'Sibling stops Connect UI pid'
Assert ($clean2 -notmatch 'Stop-CursorServerProfileTree') 'hygiene never kills whole Cursor profile tree'
Assert ($closeWin.Length -gt 40) 'Close-CursorProjectWindows exists'
Assert ($closeWin -match 'PostMessage|WM_CLOSE') 'window close uses WM_CLOSE'
Assert ($closeWin -match 'ProtectRootName') 'window close respects ProtectRootName'
Assert ($closeWin -match 'Get-CursorMainProfileProcesses') 'window close only touches server profile mains'
Assert ($closeWin -notmatch 'Get-CursorMainPersonalProcesses') 'Close-Cursor never enumerates personal Cursor'
Assert ($git -match 'Write-ConnectSessionSlotMarker') 'slot marker writer exists'
Assert ($git -match 'Get-ConnectSessionSlotMarkers') 'slot marker reader exists'
$markersFn = Get-FunctionSourceRegex $git 'Get-ConnectSessionSlotMarkers'
Assert ($markersFn -match 'Generic\.List|List\[object\]') 'markers reader uses List (not ForEach-Object += hole)'
Assert ($markersFn -notmatch 'Get-ChildItem[\s\S]{0,120}\|\s*ForEach-Object') 'markers reader avoids ForEach-Object pipeline accumulation'
Assert ($markersFn -match 'markerPid') 'markers reader avoids $pid vs automatic $PID collision'
Assert ($markersFn -notmatch '\$pid\s*=') 'markers reader has no $pid assignment'
Assert ($git -match 'UTF8Encoding::new\(\$false\)|UTF8Encoding\]::new\(\$false\)') 'marker write is UTF-8 without BOM'

Assert ($clean2 -match 'for \(\$slot = 0; \$slot -lt 10') 'Soft loops all 10 UID ports'
Assert ($clean2 -match '(?s)Mode -eq ''Soft''[\s\S]{0,4000}Remove-LocalOrphanTunnel') 'Soft arm calls Remove-LocalOrphanTunnel'
Assert ($clean2 -match '(?s)HYGIENE_SIBLING begin[\s\S]{0,800}Report\.Siblings') 'Sibling arm iterates Report.Siblings'
Assert ($clean2 -match 'protect_current') 'Sibling skips Cursor close when root equals protect'
Assert ($show -match 'Soft-clean orphans/idle') 'interactive asks soft confirm'
Assert ($show -match 'Close sibling sessions') 'interactive asks sibling confirm'
Assert ($show -match 'SkipServer') 're-scan siblings after soft without full server probe'

Assert ($ui -match 'H hygiene') 'Win session footer has H hygiene'
Assert ($ui -notmatch 'G git') 'Win session footer removed G git'
Assert ($uiSh -match 'H = hygiene') 'Mac session footer has H hygiene'
Assert ($uiSh -notmatch 'G = git mode') 'Mac session footer removed G = git mode'

Assert ($win -match "resolved = 'h'") 'Win session resolves H'
Assert ($win -match 'Show-ConnectHygieneInteractive') 'Win session calls hygiene interactive'
Assert ($win -match 'ConsoleKey]::H') 'Win H uses VK-safe ConsoleKey::H'
Assert ($win -notmatch "resolved = 'g'") 'Win session no longer resolves g'
Assert ($win -notmatch '"g" \{[^}]*Configure-GitMode') 'Win project menu removed g -> Configure-GitMode'
Assert ($win -notmatch "'3' \{ Configure-GitMode \}") 'Win config menu removed 3 -> Configure-GitMode'
Assert ($win -notmatch '3  Change git mode') 'Win config menu label removed Change git mode'
Assert ($win -notmatch 'Configure-GitMode') 'Win connect.ps1 has zero Configure-GitMode call sites'
Assert ($bat -match 'Show-ConnectHygieneInteractive') 'connect.bat guards hygiene wire'
Assert ($bat -match 'H hygiene') 'connect.bat guards H hygiene footer'

Assert ($mac -match '_resolved="h"') 'Mac session resolves h'
Assert ($mac -match 'show_connect_hygiene_interactive') 'Mac wires hygiene'
Assert ($mac -notmatch '_resolved="g"') 'Mac session no longer resolves g'
Assert ($mac -notmatch 'configure_git_mode') 'Mac has no configure_git_mode call'
Assert ($mac -notmatch 'Change git mode|3\) .*git') 'Mac menus dropped numbered git item'
Assert ($gmSh -match 'show_connect_hygiene_interactive') 'git-mode.sh has hygiene helpers'
Assert ($gmSh -match 'HYGIENE_SOFT|HYGIENE_SIBLING') 'Mac hygiene logs Soft/Sibling tags'
Assert ($gmSh -match 'Re-scan siblings after soft') 'Mac re-scans siblings after soft'

# ---------------------------------------------------------------------------
# HARD runtime: extract real report/clean bodies; stub OS side effects.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Connect hygiene HARD runtime ===' -ForegroundColor Cyan

$script:orphanPorts = New-Object System.Collections.Generic.List[int]
$script:tunnelStops = New-Object System.Collections.Generic.List[string]
$script:uiStops = New-Object System.Collections.Generic.List[int]
$script:cursorCloses = New-Object System.Collections.Generic.List[string]
$script:sshxCalls = New-Object System.Collections.Generic.List[string]
$script:fakeTunnelMap = @{}  # port -> @( @{ Pid=; UiPid= } )

function Write-GitModeLog { param([string]$Message, [string]$Level = 'INFO') }
function Get-TunnelPortUserBase { param([string]$UidStr) return 20000 }
function Get-ConnectSessionSlotMarkers {
    return @(
        [pscustomobject]@{ Slot = 1; Port = 20001; Pid = 91002; ProjectId = 'SiblingProj'; RemotePath = 'D:\work\SiblingProj' }
        [pscustomobject]@{ Slot = 2; Port = 20002; Pid = 91003; ProjectId = 'OrphanGone'; RemotePath = 'D:\work\OrphanGone' }
    )
}
function Get-LocalTunnelSshPids {
    param([int]$TargetPort)
    if ($script:fakeTunnelMap.ContainsKey($TargetPort)) {
        return @($script:fakeTunnelMap[$TargetPort] | ForEach-Object { [int]$_.Pid })
    }
    return @()
}
function Get-ConnectUiPidForProcess {
    param([int]$StartProcessId)
    foreach ($port in @($script:fakeTunnelMap.Keys)) {
        foreach ($row in @($script:fakeTunnelMap[$port])) {
            if ([int]$row.Pid -eq [int]$StartProcessId) { return [int]$row.UiPid }
        }
    }
    return 0
}
function Remove-LocalOrphanTunnel {
    param([int]$TargetPort, $CurrentBgTunnel = $null, [int[]]$ProtectedProcessIds = @())
    [void]$script:orphanPorts.Add([int]$TargetPort)
    return $true
}
function Stop-TunnelProcessWithExitLog {
    param([int]$ProcessId, [string]$Reason = '')
    [void]$script:tunnelStops.Add(("{0}:{1}" -f $ProcessId, $Reason))
}
function Close-CursorProjectWindows {
    param([string]$ProjectRootName, [string]$ProtectRootName = '', [string]$Alias = 'claude-server')
    [void]$script:cursorCloses.Add(("{0}|protect={1}" -f $ProjectRootName, $ProtectRootName))
    return 1
}
function SshX {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $joined = ($Args | ForEach-Object { "$_" }) -join ' '
    [void]$script:sshxCalls.Add($joined)
    if ($joined -match 'cursor-server-reaper') { return 'REAPER_OK' }
    if ($joined -match 'MUX_DEAD_REMOVED') { return 'MUX_DEAD_REMOVED=2' }
    return "LISTEN_BEGIN`n127.0.0.1:20001`nLISTEN_END`nMUX_BEGIN`nMUX_END`nSFTP_BEGIN`n0`nSFTP_END`nSM_BEGIN`nSM_END"
}
# Shadow Stop-Process only for hygiene sibling UI path (never call real Stop-Process here).
function Stop-Process {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Id,
        [switch]$Force
    )
    [void]$script:uiStops.Add([int]$Id)
}

# Load real hygiene functions after stubs.
foreach ($n in @('Get-ConnectHygieneReport', 'Invoke-ConnectHygieneClean')) {
    $src = Get-FunctionSource -Content $git -Name $n
    if (-not $src) { Assert $false "extract $n for HARD runtime"; continue }
    . ([scriptblock]::Create($src))
}

# Fake topology:
# 20000 current tunnel (this PID as UI)
# 20001 sibling Connect UI 91002 / tunnel 81001 / SiblingProj
# 20002 orphan tunnel 82002 / ui=0
$script:SessionBgTunnel = [pscustomobject]@{ Id = 80000; HasExited = $false }
$script:fakeTunnelMap[20000] = @(@{ Pid = 80000; UiPid = [int]$PID })
$script:fakeTunnelMap[20001] = @(@{ Pid = 81001; UiPid = 91002 })
$script:fakeTunnelMap[20002] = @(@{ Pid = 82002; UiPid = 0 })

$r = Get-ConnectHygieneReport -UidStr '1000' -ProtectRemotePath 'D:\work\CurrentProj' -ProtectProjectId 'CurrentProj'
Assert ($r.ProtectRootName -eq 'CurrentProj') 'HARD report ProtectRootName from remote path'
Assert ($r.SoftTargetCount -eq 1) 'HARD report SoftTargetCount=1 orphan'
Assert ($r.SiblingCount -eq 1) 'HARD report SiblingCount=1 sibling'
$classes = @($r.Tunnels | ForEach-Object { '{0}:{1}' -f $_.Port, $_.Class })
Assert ($classes -contains '20000:current') 'HARD classifies current tunnel'
Assert ($classes -contains '20001:sibling') 'HARD classifies sibling tunnel'
Assert ($classes -contains '20002:orphan') 'HARD classifies orphan tunnel'

$script:orphanPorts.Clear(); $script:tunnelStops.Clear(); $script:uiStops.Clear(); $script:cursorCloses.Clear(); $script:sshxCalls.Clear()
$soft = Invoke-ConnectHygieneClean -Mode Soft -Report $r -ProtectRemotePath 'D:\work\CurrentProj' -ProtectProjectId 'CurrentProj'
# Soft only Remove-LocalOrphanTunnel on ports that still have local -R (not empty slots).
Assert ($script:orphanPorts.Count -eq 3) 'HARD Soft Remove on live local -R ports only (3)'
Assert ((@($script:orphanPorts | Sort-Object -Unique) -join ',') -eq '20000,20001,20002') 'HARD Soft Remove ports are the three live tunnels'
Assert ($script:tunnelStops.Count -eq 0) 'HARD Soft never Stop-TunnelProcessWithExitLog'
Assert ($script:uiStops.Count -eq 0) 'HARD Soft never Stop-Process Connect UI'
Assert ($script:cursorCloses.Count -eq 0) 'HARD Soft never Close-CursorProjectWindows'
Assert (($script:sshxCalls | Where-Object { $_ -match 'cursor-server-reaper' }).Count -ge 1) 'HARD Soft fail-open calls cursor-server-reaper'
Assert ($soft.MuxCleaned -eq 2) 'HARD Soft parses MUX_DEAD_REMOVED'

$script:orphanPorts.Clear(); $script:tunnelStops.Clear(); $script:uiStops.Clear(); $script:cursorCloses.Clear(); $script:sshxCalls.Clear()
$sib = Invoke-ConnectHygieneClean -Mode Sibling -Report $r -ProtectRemotePath 'D:\work\CurrentProj' -ProtectProjectId 'CurrentProj'
Assert ($script:orphanPorts.Count -eq 0) 'HARD Sibling never calls Remove-LocalOrphanTunnel'
Assert ($script:tunnelStops -contains '81001:hygiene_sibling') 'HARD Sibling stops sibling tunnel with hygiene_sibling'
Assert (-not ($script:tunnelStops | Where-Object { $_ -like '80000:*' })) 'HARD Sibling never stops current tunnel'
Assert (-not ($script:tunnelStops | Where-Object { $_ -like '82002:*' })) 'HARD Sibling does not treat orphan as sibling stop'
Assert ($script:uiStops -contains 91002) 'HARD Sibling stops sibling Connect UI pid'
Assert (-not ($script:uiStops -contains [int]$PID)) 'HARD Sibling never stops current Connect PID'
Assert ($script:cursorCloses.Count -eq 1) 'HARD Sibling closes one Cursor project window'
Assert ($script:cursorCloses[0] -match '^SiblingProj\|protect=CurrentProj$') 'HARD Sibling closes SiblingProj protecting CurrentProj'
Assert ($sib.SiblingTunnels -eq 1 -and $sib.SiblingConnects -eq 1) 'HARD Sibling counters tunnels=1 connects=1'

# Protect-current: sibling row claims same project root as protect -> Cursor step skipped
$rProtect = [pscustomobject]@{
    PortBase         = 20000
    CurrentPid       = [int]$PID
    CurrentTunnelPid = 80000
    ProtectRootName  = 'SiblingProj'
    ProtectRemotePath = 'D:\work\SiblingProj'
    Markers          = @()
    Tunnels          = @()
    OrphanTunnelPids = @()
    Siblings         = @(
        [pscustomobject]@{ Port = 20001; Slot = 1; TunnelPid = 81001; ConnectUiPid = 91002; Class = 'sibling'; ProjectId = 'SiblingProj'; RemotePath = 'D:\work\SiblingProj' }
    )
    SoftTargetCount  = 0
    SiblingCount     = 1
    Server           = [pscustomobject]@{ Ok = $false }
}
$script:orphanPorts.Clear(); $script:tunnelStops.Clear(); $script:uiStops.Clear(); $script:cursorCloses.Clear()
$null = Invoke-ConnectHygieneClean -Mode Sibling -Report $rProtect -ProtectRemotePath 'D:\work\SiblingProj' -ProtectProjectId 'SiblingProj'
Assert ($script:tunnelStops -contains '81001:hygiene_sibling') 'HARD protect-same-root still stops sibling tunnel'
Assert ($script:uiStops -contains 91002) 'HARD protect-same-root still stops sibling Connect UI'
Assert ($script:cursorCloses.Count -eq 0) 'HARD protect-same-root skips Cursor window close'

# Extra adversarial: Soft must not iterate Report.Siblings; Sibling must not call reaper
Assert ($clean2 -match '(?s)Mode -eq ''Soft''[\s\S]*?return \$result[\s\S]*?HYGIENE_SIBLING begin') 'Soft returns before Sibling arm'
Assert ($clean2 -notmatch '(?s)Mode -eq ''Sibling''[\s\S]{0,2000}cursor-server-reaper') 'Sibling arm never runs cursor-server-reaper'
Assert ($closeWin -match 'equals_protect|skip root') 'Close-Cursor skips when root equals protect'
Assert ($closeWin -match 'shared profile; skipped process kill') 'Close-Cursor documents shared-profile no process-kill'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
