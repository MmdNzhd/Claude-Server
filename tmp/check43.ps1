$e=$null
[void][System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1',[ref]$null,[ref]$e)
if($e -and $e.Count){ 'PARSE_FAIL el'; $e|Select-Object -First 5|ForEach-Object{$_.ToString()} } else { 'PARSE_OK el' }
$e=$null
[void][System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',[ref]$null,[ref]$e)
if($e -and $e.Count){ 'PARSE_FAIL connect'; $e|Select-Object -First 5|ForEach-Object{$_.ToString()} } else { 'PARSE_OK connect' }
'VER=' + (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Pattern 'elevated_direct_fallback|Get-InteractiveWindowsUserQualified|LOGON_WITH_PROFILE' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
