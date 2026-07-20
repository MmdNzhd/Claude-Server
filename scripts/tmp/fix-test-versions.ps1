$ErrorActionPreference = 'Stop'

function Replace-InFile([string]$Path, [string]$Old, [string]$New) {
    $c = [IO.File]::ReadAllText((Resolve-Path $Path))
    if (-not $c.Contains($Old)) { throw "pattern not found in $Path : $Old" }
    $c2 = $c.Replace($Old, $New)
    [IO.File]::WriteAllText((Resolve-Path $Path), $c2)
    Write-Host "OK $Path"
}

$oldPat = 'no_ssh_proc|tcp_open_no_process|no_process_tcp_open'
$newPat = 'no_ssh_proc|tcp_open_no_process|no_process_tcp_open|no_proc_tcp_open'
Replace-InFile 'scripts/client/tests/test-connect-pipeline.ps1' $oldPat $newPat
Replace-InFile 'scripts/client/tests/test-git-mode-deep.ps1' $oldPat $newPat

# Bump embedded versions
$win = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/windows/connect.ps1'))
$win2 = $win.Replace("ConnectVersion = '20260719.21'", "ConnectVersion = '20260719.22'")
if ($win2 -eq $win) { throw 'connect.ps1 version not bumped' }
[IO.File]::WriteAllText((Resolve-Path 'scripts/client/windows/connect.ps1'), $win2)
Write-Host 'OK connect.ps1 version .22'

$mac = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/mac/connect.sh'))
# Mac still on .14 in CONNECT_VERSION - align to .22
if ($mac -match "CONNECT_VERSION='([^']+)'") {
    $mac2 = $mac -replace "CONNECT_VERSION='[^']+'", "CONNECT_VERSION='20260719.22'"
    [IO.File]::WriteAllText((Resolve-Path 'scripts/client/mac/connect.sh'), $mac2)
    Write-Host "OK mac CONNECT_VERSION was $($Matches[1]) -> .22"
}

Write-Host 'DONE'
