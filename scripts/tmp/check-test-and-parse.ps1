$ErrorActionPreference='Stop'
$el='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$tt='D:\Smart\Claude-Code-Server\scripts\client\tests\test-editor-launch-strategies.ps1'
$e=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($el,[ref]$null,[ref]$e)
if($e){ $e | ForEach-Object { Write-Host $_.ToString() }; throw 'editor-launch parse fail' }
Write-Host 'editor-launch.ps1 syntax OK'
Select-String -Path $tt -Pattern 'preserve_open_windows|LAUNCH_RETRY_NO_KILL|pre_launch|retry_before' |
  ForEach-Object { $_.Line.Trim() }
Write-Host '---- verify source ----'
$src = Get-Content $el -Raw
if ($src -match "pre_launch_agent_or_new_window' -Force") { throw 'force kill still present' }
if ($src -notmatch 'preserve_open_windows') { throw 'preserve skip missing' }
if ($src -notmatch 'LAUNCH_RETRY_NO_KILL') { throw 'retry no kill missing' }
Write-Host 'source checks OK'
Write-Host 'version:' (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
