# _diag-cursor-launch.ps1 — inspect Cursor remote processes + test launch path
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
. (Join-Path (Split-Path (Get-ClientFile 'windows\connect.ps1') -Parent) '..\editor-launch.ps1')

$Alias = 'claude-server'
$remotePath = '/home/smart/mounts/ai'

Write-Host '=== Cursor remote processes ===' -ForegroundColor Cyan
$procs = @(Get-RemoteEditorProcesses -EditorCmd 'cursor' -Alias $Alias -RemotePath $remotePath)
Write-Host "  matching Get-RemoteEditorProcesses: $($procs.Count)"
Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'folder-uri|ssh-remote|claude-server|mounts' } |
    ForEach-Object {
        Write-Host "  pid $($_.ProcessId): $($_.CommandLine)"
    }
Write-Host ''
Write-Host '=== all main Cursor (no --type=) ===' -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -notmatch '--type=' } |
    ForEach-Object {
        $cmd = $_.CommandLine
        if ($cmd.Length -gt 400) { $cmd = $cmd.Substring(0, 400) + '...' }
        Write-Host "  pid $($_.ProcessId): $cmd"
    }

Write-Host ''
Write-Host '=== cursor.cmd path ===' -ForegroundColor Cyan
$cli = Ensure-EditorOnPath 'cursor'
Write-Host "  cli: $cli"
Write-Host "  admin: $([bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

Write-Host ''
Write-Host '=== profile dir ===' -ForegroundColor Cyan
Write-Host "  $(Get-CursorRemoteProfileDir)"
