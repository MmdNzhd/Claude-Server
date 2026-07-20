$ErrorActionPreference='Stop'
foreach ($rel in @(
  'scripts\client\connect-ui.ps1',
  'scripts\client\windows\connect.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\windows\connect-update.ps1'
)) {
  $p = "D:\Smart\Claude-Code-Server\$rel"
  $t = [IO.File]::ReadAllText($p)
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count) {
    $errs | Select-Object -First 8 | ForEach-Object { $_.ToString() }
    throw "parse fail $rel"
  }
  Write-Host "OK $rel"
}
$ui=[IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1')
if ($ui -notmatch 'function Read-ConnectPrompt') { throw 'no Read-ConnectPrompt' }
if ($ui -notmatch 'function Write-ConnectDecision') { throw 'no Write-ConnectDecision' }
$c=[IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
if ($c -notmatch 'Write-ConnectDecision') { throw 'connect missing decisions' }
Write-Host 'all good'
