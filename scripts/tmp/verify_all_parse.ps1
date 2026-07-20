$ErrorActionPreference='Stop'
$files=@(
  'scripts\client\connect-ui.ps1',
  'scripts\client\windows\connect.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\editor-launch.ps1',
  'scripts\client\cursor-auth-laptop.ps1'
)
foreach($rel in $files){
  $p="D:\Smart\Claude-Code-Server\$rel"
  $t=[IO.File]::ReadAllText($p)
  $errs=$null
  $null=[System.Management.Automation.Language.Parser]::ParseInput($t,[ref]$null,[ref]$errs)
  if($errs -and $errs.Count){
    Write-Host "FAIL $rel"
    $errs | Select-Object -First 5 | ForEach-Object { $_.ToString() }
    throw "parse $rel"
  }
  Write-Host "OK $rel"
}
$c=[IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
$left=([regex]::Matches($c,'Read-Host.*Press Enter')).Count
Write-Host "PressEnter_left=$left"
if($left -gt 0){ throw 'still have Press Enter Read-Host' }
if($c -notmatch 'Wait-ConnectExit'){ throw 'no Wait-ConnectExit usage' }
Write-Host ALL_GOOD
