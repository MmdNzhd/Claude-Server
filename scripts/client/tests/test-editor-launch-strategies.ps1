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
Assert ($launchSrc -match 'LAUNCH_KILL: reason=auth_relaunch') 'AuthRelaunch soft-stops profile'
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


Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
