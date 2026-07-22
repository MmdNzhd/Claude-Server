$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1', [ref]$null, [ref]$e)
if ($e -and $e.Count) { 'PARSE_FAIL'; $e | Select-Object -First 8 | ForEach-Object { $_.ToString() } } else { 'PARSE_OK' }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Pattern 'function Set-CursorProxySettings|function Get-RunningCursorProxySocksPort|proxy_settings_changed|preserved_open_windows|function Open-RemoteEditor|Get-CursorProxyLaunchArgs' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
