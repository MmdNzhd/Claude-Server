$ErrorActionPreference="Continue"
function Test-Pe([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $fs=[IO.File]::OpenRead($Path)
  try {
    $h=New-Object byte[] 64
    if ($fs.Read($h,0,64) -lt 64) { return $false }
    if ($h[0] -ne 0x4D -or $h[1] -ne 0x5A) { return $false }
    $off=[BitConverter]::ToInt32($h,0x3C)
    $null=$fs.Seek([int64]$off,[IO.SeekOrigin]::Begin)
    $s=New-Object byte[] 4
    if ($fs.Read($s,0,4) -ne 4) { return $false }
    return ($s[0]-eq 0x50 -and $s[1]-eq 0x45 -and $s[2]-eq 0 -and $s[3]-eq 0)
  } finally { $fs.Dispose() }
}
$good = Join-Path $env:USERPROFILE "Desktop\Claude-Connect.exe"
if (-not (Test-Pe $good)) { throw "Desktop EXE not valid PE" }
$targets = @(
  (Join-Path $env:USERPROFILE "Desktop\Claude-Connect\Claude-Connect.exe"),
  "C:\Users\Smart\Downloads\claude-code-client-20260715.QUARANTINE-DO-NOT-RUN-20260721-214141\windows\Claude-Connect.exe"
)
foreach ($t in $targets) {
  if (-not (Test-Path $t)) { Write-Host "skip missing $t"; continue }
  if (Test-Pe $t) { Write-Host "already ok $t"; continue }
  Copy-Item -LiteralPath $good -Destination $t -Force
  Write-Host "repaired $t -> $((Get-Item $t).Length)"
}
# sync fixed bootstrap/update into canon
$canon = Join-Path $env:USERPROFILE "Desktop\Claude-Connect"
Copy-Item "scripts\client\windows\connect-bootstrap.ps1" (Join-Path $canon "connect-bootstrap.ps1") -Force
Copy-Item "scripts\client\windows\connect-update.ps1" (Join-Path $canon "connect-update.ps1") -Force
Write-Host "canon scripts synced"
