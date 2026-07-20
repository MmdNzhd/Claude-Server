$ErrorActionPreference='Stop'
foreach ($rel in @(
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\connect-ui.ps1'
)) {
  $p = "D:\Smart\Claude-Code-Server\$rel"
  $t = [IO.File]::ReadAllText($p)
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count) {
    $errs | ForEach-Object { $_.ToString() }
    throw "parse fail $rel"
  }
  Write-Host "OK $rel"
}
$ui = [IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1')
if ($ui -notmatch 'Get-ConnectLogDir') { throw 'missing Get-ConnectLogDir' }
if ($ui -notmatch 'Keep durable local') { throw 'missing keep durable' }
if ($ui -match 'temp buffer only on laptop') { throw 'still has temp-only message' }
Write-Host 'markers OK'
