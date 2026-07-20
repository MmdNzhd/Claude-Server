$ErrorActionPreference='Stop'
foreach ($rel in @('scripts\client\connect-ui.ps1','scripts\client\windows\connect-update.ps1')) {
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
foreach ($m in @('Read-ConnectLogSyncWatermark','Get-ConnectLogSyncTarget','ConnectSessionId','zero-loss')) {
  if ($ui -notmatch [regex]::Escape($m) -and $m -ne 'zero-loss') {
    if ($ui -notmatch $m) { throw "missing $m" }
  }
}
if ($ui -notmatch 'Read-ConnectLogSyncWatermark') { throw 'no watermark' }
if ($ui -notmatch 'Get-ConnectLogSyncTarget') { throw 'no sync target' }
if ($ui -notmatch 'ConnectSessionId') { throw 'no session id' }
Write-Host 'markers OK'
# exit 2 block shouldn't be duplicated weirdly
$cu = [IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1')
$c = ([regex]::Matches($cu, 'exit 2')).Count
Write-Host "exit2_count=$c"
if ($cu -notmatch 'SSH_STAGE') { throw 'no SSH_STAGE' }
Write-Host 'update markers OK'
