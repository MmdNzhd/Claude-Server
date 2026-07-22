$ErrorActionPreference = 'Stop'
$gm = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$lines = [IO.File]::ReadAllLines($gm)
# find Ensure uid and Release-Stale lines
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'ENSURE_TUNNEL skip_acquire|id -u|Release-StaleTunnelPort|adopt_local') {
    Write-Host ("{0}: {1}" -f ($i+1), $lines[$i])
  }
}
