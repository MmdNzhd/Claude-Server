#Requires -Version 5.1
# Stage 6: windows-mcp must not leave orphan cmd.exe /c start-server.cmd parents.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}
function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Stage 6: windows-mcp no orphan cmd ===' -ForegroundColor White

$mcp = Get-Content (Get-ClientFile 'windows\windows-mcp-laptop.ps1') -Raw
$direct = Get-FunctionSource $mcp 'Start-WindowsMcpProcessDirect'
$reaper = Get-FunctionSource $mcp 'Stop-WindowsMcpOrphanCmdWrappers'
$start = Get-FunctionSource $mcp 'Start-WindowsMcpIfNeeded'
$restart = Get-FunctionSource $mcp 'Restart-WindowsMcpServer'

Assert ($direct.Length -gt 80) 'Start-WindowsMcpProcessDirect exists'
Assert ($direct -match 'CreateNoWindow\s*=\s*\$true') 'Direct start sets CreateNoWindow=true'
Assert ($direct -match 'UseShellExecute\s*=\s*\$false') 'Direct start sets UseShellExecute=false'
Assert ($direct -match 'started_via_windows_mcp_exe|started_via_python_direct') 'Logs started_via_windows_mcp_exe or python_direct'
Assert ($direct -match 'windows_mcp|Get-WindowsMcpExe|Get-PythonLauncher') 'Uses exe or python -m windows_mcp path'

Assert ($reaper.Length -gt 40) 'Stop-WindowsMcpOrphanCmdWrappers exists'
Assert ($reaper -match 'start-server\.cmd' -and $reaper -match 'orphan_cmd_reaped') 'Orphan reaper targets start-server.cmd wrappers'

Assert ($start -match 'Start-WindowsMcpProcessDirect') 'Start-WindowsMcpIfNeeded uses direct helper'
Assert ($restart -match 'Start-WindowsMcpProcessDirect') 'Restart-WindowsMcpServer uses direct helper'
Assert ($start -match 'Stop-WindowsMcpOrphanCmdWrappers') 'Start path calls orphan reaper'
Assert ($restart -match 'Stop-WindowsMcpOrphanCmdWrappers') 'Restart path calls orphan reaper'

# No bare Start-Process of start-server.cmd in start/restart (allow mention in reaper/comments only)
$badStart = [regex]::IsMatch($start, 'Start-Process\s+-FilePath\s+\$cmd')
$badRestart = [regex]::IsMatch($restart, 'Start-Process\s+-FilePath\s+\$cmd')
Assert (-not $badStart) 'Start-WindowsMcpIfNeeded does not Start-Process start-server.cmd'
Assert (-not $badRestart) 'Restart-WindowsMcpServer does not Start-Process start-server.cmd'
Assert ($mcp -notmatch "started_via_start-server\.cmd") 'Legacy started_via_start-server.cmd log removed'

# auto_relaunch_skip cursor_settings (connect.ps1)
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($win -match 'auto_relaunch_skip reason=cursor_settings') 'connect.ps1 logs auto_relaunch_skip reason=cursor_settings'
Assert ($win -match '\(\?i\)settings') 'connect.ps1 checks Settings window title before auto_relaunch'

$el = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
$ah = Get-FunctionSource $el 'Test-RemoteEditorInAgentHome'
Assert ($ah -match '\(\?i\)settings') 'Test-RemoteEditorInAgentHome excludes Settings titles'
Assert ($ah -match 'Test-CursorWindowShowsAgentHome') 'Agent-home still uses Test-CursorWindowShowsAgentHome'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
