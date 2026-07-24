# test-editor-launch-strategies.ps1 - launch arg strategies + URI format (no Windows process APIs)
# Callers: scripts/client/tests/run-all.bat (via manual or CI on Windows laptop)
# API under test: Get-RemoteFolderUri, Get-RemoteEditorLaunchStrategies, Get-RemoteEditorLaunchDiag
# User request: add --classic/--remote fallbacks + comprehensive launch logging, then test
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

. (Get-ClientFile 'editor-launch.ps1')

Write-Host ""
Write-Host "=== Editor launch strategies ===" -ForegroundColor Cyan
Write-Host ""

$alias = 'claude-server'
$path = '/home/smart/mounts/ai'
$uri = Get-RemoteFolderUri -Alias $alias -RemotePath $path

Assert ($uri -eq 'vscode-remote://ssh-remote+claude-server/home/smart/mounts/ai') "Get-RemoteFolderUri format"
Assert (Get-Command Get-RemoteEditorLaunchStrategies -ErrorAction SilentlyContinue) 'Get-RemoteEditorLaunchStrategies defined'
Assert (Get-Command Get-RemoteEditorProcessSnapshot -ErrorAction SilentlyContinue) 'Get-RemoteEditorProcessSnapshot defined'
Assert (Get-Command Write-EditorLaunchSnapshot -ErrorAction SilentlyContinue) 'Write-EditorLaunchSnapshot defined'
Assert (Get-Command Get-RemoteEditorStateExplain -ErrorAction SilentlyContinue) 'Get-RemoteEditorStateExplain defined'
Assert (Get-Command Write-EditorLaunchVerboseState -ErrorAction SilentlyContinue) 'Write-EditorLaunchVerboseState defined'
Assert (Get-Command Stop-CursorServerProfileTreeIfNeeded -ErrorAction SilentlyContinue) 'Stop-CursorServerProfileTreeIfNeeded defined'

$cursorStrategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd 'cursor' -Alias $alias -RemotePath $path -Uri $uri -NewWindow)
Assert ($cursorStrategies.Count -eq 4) 'cursor has 4 launch strategies'
Assert ($cursorStrategies[0].Name -eq 'folder-uri-classic') 'first strategy is folder-uri-classic'
Assert ($cursorStrategies[0].Args -contains '--classic') 'folder-uri-classic includes --classic'
Assert ($cursorStrategies[0].Args -contains '--folder-uri') 'folder-uri-classic includes --folder-uri'
Assert ($cursorStrategies[0].Args -contains '--new-window') 'cursor strategies use --new-window when requested'
Assert ($cursorStrategies[0].Args -contains '--user-data-dir') 'cursor strategies use isolated profile'

$remoteClassic = $cursorStrategies | Where-Object { $_.Name -eq 'remote-classic' } | Select-Object -First 1
Assert ($null -ne $remoteClassic) 'remote-classic strategy exists'
Assert ($remoteClassic.Args -contains '--remote') 'remote-classic includes --remote'
Assert ($remoteClassic.Args -contains 'ssh-remote+claude-server') 'remote-classic authority matches alias'
Assert ($remoteClassic.Args -contains $path) 'remote-classic includes absolute remote path'

$codeStrategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd 'code' -Alias $alias -RemotePath $path -Uri $uri -NewWindow)
Assert ($codeStrategies.Count -eq 2) 'code has 2 launch strategies'
Assert (-not ($codeStrategies[0].Args -contains '--classic')) 'VS Code strategies omit --classic'
Assert ($codeStrategies[0].Args -contains '--user-data-dir') 'code strategies use isolated profile'
Assert ((Get-Command Get-CodeRemoteProfileDir -ErrorAction SilentlyContinue)) 'Get-CodeRemoteProfileDir defined'
Assert ((Get-CodeRemoteProfileDir) -match 'ClaudeServerCodeProfile') 'VS Code profile is ClaudeServerCodeProfile'

Assert (Get-Command Test-CursorWindowTitleIsAgentHome -ErrorAction SilentlyContinue) 'Test-CursorWindowTitleIsAgentHome defined'

$explain = Get-RemoteEditorStateExplain -EditorCmd 'cursor' -Alias $alias -RemotePath $path
Assert (-not (Test-CursorWindowTitleIsAgentHome -Title '[Claude Server] ai' -ProjectRootName 'ai')) 'Claude Server title with project is not agent home'
Assert (Test-CursorWindowTitleIsAgentHome -Title 'Cursor Agents' -ProjectRootName 'ai') 'Agents title without project in title is agent home'
Assert ($explain -match 'target_uri=') 'Get-RemoteEditorStateExplain includes target_uri'
Assert ($explain -match 'on_folder=') 'Get-RemoteEditorStateExplain includes on_folder'

$launchSrc = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($launchSrc -match 'param\([\s\S]*KnownOnFolder') 'Launch-RemoteEditor has KnownOnFolder param'
Assert ($launchSrc -match 'AuthRelaunch') 'Launch-RemoteEditor has AuthRelaunch param'
Assert ($launchSrc -match 'auth_relaunch_never_kill|hard_refuse_') 'AuthRelaunch never soft-stops profile'
Assert ($launchSrc -match 'if \(\$onFolder -and -not \$agentHome\)[\s\S]{0,600}LAUNCH_SKIP') 'F1 early skip before verbose'
Assert ($launchSrc -notmatch 'SKIP_ALREADY_ON_FOLDER') 'F1 removed SKIP verbose block'
Assert ($launchSrc -match '\$script:VerboseLaunch') 'F3 VerboseLaunch defined'
Assert ($launchSrc -match 'Invoke-CimCursorProcessQuery') 'F5 CIM cache wrapper'
Assert ($launchSrc -match 'Test-RemoteEditorWindowOpenWhenOnFolder') 'single-pass window check helper'
Assert ($launchSrc -match 'Write-LaunchPerfLog') 'PERF launch logging'
Assert ($launchSrc -match 'launch_total') 'launch_total perf mark'
Assert ($launchSrc -match 'LAUNCH_KILL_SKIP: reason=preserve_open_windows') 'launch skips force-kill to preserve open windows'
Assert ($launchSrc -match 'LAUNCH_RETRY_NO_KILL') 'launch retry does not force-kill profile tree'
Assert ($launchSrc -notmatch "Stop-CursorServerProfileTreeIfNeeded -Reason 'pre_launch_agent_or_new_window' -Force") 'pre_launch force-kill removed'
Assert ($launchSrc -notmatch 'retry_before_\$\(\$strategy\.Name\)' ) 'retry force-kill removed'

# Multi-session race fix: a sibling connect session's window can appear microseconds after
# our entry-time profile_main check, so "orphan_helpers" (profile_all>0, profile_main=False)
# must request --new-window too - not just true "profile_open" (profile_main=True). Before
# the fix, orphan_helpers computed use_new_window=False, and Cursor's single-instance IPC
# could silently reroute our "open folder" request into the sibling session's window instead
# of spawning ours (confirmed live: launch spent minutes retrying against the wrong project).
Assert (Get-Command Get-CursorLaunchWindowPlan -ErrorAction SilentlyContinue) 'Get-CursorLaunchWindowPlan defined'

$planCold = Get-CursorLaunchWindowPlan -AgentHome $false -HasProfileWindow $false -ProfileProcCount 0
Assert ($planCold.Reason -eq 'cold_start') 'plan: no profile activity at all -> cold_start'
Assert ($planCold.UseNewWindow -eq $false) 'plan: cold_start does not need --new-window (nothing to collide with)'

$planOrphan = Get-CursorLaunchWindowPlan -AgentHome $false -HasProfileWindow $false -ProfileProcCount 9
Assert ($planOrphan.Reason -eq 'orphan_helpers') 'plan: helper processes with no classified main -> orphan_helpers'
Assert ($planOrphan.UseNewWindow -eq $true) 'plan: orphan_helpers now requests --new-window too (race fix)'

$planOpen = Get-CursorLaunchWindowPlan -AgentHome $false -HasProfileWindow $true -ProfileProcCount 9
Assert ($planOpen.Reason -eq 'profile_open') 'plan: classified main window present -> profile_open'
Assert ($planOpen.UseNewWindow -eq $true) 'plan: profile_open requests --new-window'

$planAgent = Get-CursorLaunchWindowPlan -AgentHome $true -HasProfileWindow $false -ProfileProcCount 0
Assert ($planAgent.Reason -eq 'agent_home') 'plan: agent_home takes priority over other reasons'
Assert ($planAgent.UseNewWindow -eq $true) 'plan: agent_home requests --new-window'

Assert ($launchSrc -match 'Get-CursorLaunchWindowPlan -AgentHome \$agentHome -HasProfileWindow \$hasProfileWindow -ProfileProcCount \$profileProcCount') 'Launch-RemoteEditor delegates plan decision to the testable helper'

# Recovery cold-launch poll budget: a cold Cursor.exe start after soft_stop_profile has to
# spin up its whole process tree from disk with no warm profile process to reuse - on a
# loaded machine this routinely exceeds the old 10s budget (20*500ms) while still succeeding
# a bit later (confirmed live: the window appeared correctly ~30-60s after the old loop had
# already given up and reported failure). Guard the widened budget against regression.
Assert ($launchSrc -match 'for \(\$tick = 1; \$tick -le 90; \$tick\+\+\)') 'recovery cold-launch poll budget widened to 90 ticks (45s, was 20/10s)'
Assert ($launchSrc -notmatch 'for \(\$tick = 1; \$tick -le 20; \$tick\+\+\)') 'old too-short 20-tick recovery budget removed'

Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
