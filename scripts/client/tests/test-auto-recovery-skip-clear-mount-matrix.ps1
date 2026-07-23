#Requires -Version 5.1
# Stage 4: auto-recovery CLEAR_MOUNT decision matrix uses presence API.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Stage 4: auto-recovery skip-clear matrix ===' -ForegroundColor White
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$el = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw

# Extract auto-recovery decision block (not manual R continue)
$m = [regex]::Match($win, '(?s)\$skipRecoveryClear = \$false.*?Clear-SessionMount -ProjectId \$go\.Id.*?Reason ''auto_recovery''')
Assert ($m.Success) 'Auto-recovery CLEAR_MOUNT block found'
$block = if ($m.Success) { $m.Value } else { '' }

Assert ($block -match 'Get-RemoteEditorSessionPresence') 'Recovery block calls Get-RemoteEditorSessionPresence'
Assert ($block -notmatch 'Test-RemoteEditorWindowOpen\s*-') 'Recovery block does not call Test-RemoteEditorWindowOpen'
Assert ($block -match 'editor_window_open_not_on_folder') 'Logs editor_window_open_not_on_folder'
Assert ($block -match 'editor_check_failed_sticky') 'Logs editor_check_failed_sticky'
Assert ($block -match 'presence\.OnFolder|\$presence\.OnFolder') 'Uses presence.OnFolder'
Assert ($block -match 'presence\.WindowOpen|\$presence\.WindowOpen') 'Uses presence.WindowOpen'

# Dead-code proof on WindowOpen API still true for auth gates elsewhere
Assert ($el -match '(?s)function Test-RemoteEditorWindowOpen.*?Test-RemoteEditorOnCorrectFolder') 'WindowOpen API still requires on-folder (auth gate)'
Assert ($el -match 'function Get-RemoteEditorSessionPresence') 'Presence API exists'

# Manual R must not Clear-SessionMount in that branch
$manual = [regex]::Match($win, '(?s)if \(\$action -eq ''r''\) \{.*?continue sessionLoop')
Assert ($manual.Success) 'Manual R branch found'
# First continue sessionLoop after Begin-ConnectRecovery manual should not Clear-SessionMount before it
$manChunk = if ($manual.Success) { $manual.Value } else { '' }
# The manual path with $gotKey continues without Clear-SessionMount
Assert ($manChunk -match 'Trigger ''manual''') 'Manual R uses Trigger manual'
Assert ($manChunk -notmatch 'Reason ''auto_recovery''') 'Manual R chunk (to first continue) has no auto_recovery clear'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
