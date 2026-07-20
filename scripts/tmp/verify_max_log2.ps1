$ErrorActionPreference='Stop'
$t=[IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
$errs=$null
$null=[System.Management.Automation.Language.Parser]::ParseInput($t,[ref]$null,[ref]$errs)
if($errs -and $errs.Count){$errs|%{$_.ToString()}; throw 'fail'}
Write-Host 'connect.ps1 parse OK'
