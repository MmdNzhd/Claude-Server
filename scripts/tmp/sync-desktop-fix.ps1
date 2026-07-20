$ErrorActionPreference='Stop'
$src = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$ver = (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
$dstRoot = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows'
if (-not (Test-Path $dstRoot)) { throw "Desktop package missing: $dstRoot" }
Copy-Item $src (Join-Path $dstRoot 'editor-launch.ps1') -Force
Copy-Item 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' (Join-Path $dstRoot 'connect.ps1') -Force
Copy-Item 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' (Join-Path $dstRoot 'connect-version.txt') -Force
# verify no force kill in desktop copy
$desk = Get-Content (Join-Path $dstRoot 'editor-launch.ps1') -Raw
if ($desk -match "pre_launch_agent_or_new_window' -Force") { throw 'Desktop still has force kill' }
if ($desk -notmatch 'preserve_open_windows') { throw 'Desktop missing preserve skip' }
$deskVer = (Get-Content (Join-Path $dstRoot 'connect-version.txt') -Raw).Trim()
Write-Host "Desktop package synced to v$deskVer"
Write-Host "Repo version: $ver"
