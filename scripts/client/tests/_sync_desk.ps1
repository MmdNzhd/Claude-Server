$ErrorActionPreference = 'Stop'
$src = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$dst = 'C:\Users\Smart\Desktop\Claude-Connect\connect.ps1'
if (-not (Test-Path $dst)) { throw 'Desktop Claude-Connect\connect.ps1 missing' }
Copy-Item -LiteralPath $src -Destination $dst -Force
$t = Get-Content $dst -Raw
$ver = if ($t -match "ConnectVersion = '([^']+)'") { $Matches[1] } else { '?' }
Write-Host ("DESK_SYNCED ver=$ver")
Write-Host ("has_presence=" + [bool]($t -match 'Get-RemoteEditorSessionPresence'))
Write-Host ("has_reassert=" + [bool]($t -match 'RECOVERY_MOUNTOK_REASSERT'))
Write-Host ("has_settings_skip=" + [bool]($t -match 'auto_relaunch_skip reason=cursor_settings'))
Write-Host ("has_refuse=" + [bool]($t -match 'claude-code-sepidz'))
