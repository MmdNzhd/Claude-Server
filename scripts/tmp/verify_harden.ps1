$ErrorActionPreference = 'Stop'
$cu = [IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1')
if ($cu -notmatch 'Resolve-UpdateEndpoint') { throw 'missing Resolve' }
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($cu, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse errors' }
Write-Host 'connect-update parse OK'

$ib = [IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\server\commands\install-client-bundle.sh')
if ($ib -notmatch '_sync_sepidz_update_keys') { throw 'install missing sync' }
Write-Host 'install-client-bundle OK'

$au = [IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\server\commands\add-user.sh')
if ($au -notmatch 'timeout 10') { throw 'add-user missing timeout' }
if ($au -notmatch 'sepidz update keys refreshed') { throw 'add-user missing key sync' }
Write-Host 'add-user OK'

# show main flow still intact
if ($cu -notmatch 'Test-RemoteVersionNewer') { throw 'lost version compare' }
if ($cu -notmatch 'Invoke-BundleDownload') { throw 'lost download' }
Write-Host 'flow markers OK'
