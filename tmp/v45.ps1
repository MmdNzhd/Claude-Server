$e=$null
[void][System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1',[ref]$null,[ref]$e)
if($e -and $e.Count){ 'PARSE_FAIL'; $e|Select-Object -First 3|%{$_.ToString()} } else { 'PARSE_OK' }
$el=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Raw
if($el -match 'proxy_settings_changed'){ 'BAD proxy kill still present' } else { 'OK no proxy_settings_changed' }
if($el -match 'preserved_open_windows'){ 'OK preserve' } else { 'BAD' }
if($el -match 'auth_relaunch_preserve_open_windows'){ 'OK auth preserve' } else { 'BAD auth' }
Copy-Item 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' 'C:\Users\Smart\Desktop\Claude-Connect\editor-launch.ps1' -Force
Copy-Item 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' 'C:\Users\Smart\Desktop\Claude-Connect\connect.ps1' -Force
Copy-Item 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' 'C:\Users\Smart\Desktop\Claude-Connect\connect-version.txt' -Force
'VER='+(Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
'BUNDLE_HAS_PRESERVE=' + [bool](Select-String -Path 'C:\Users\Smart\Desktop\Claude-Connect\editor-launch.ps1' -Pattern 'preserved_open_windows' -Quiet)
