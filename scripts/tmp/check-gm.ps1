$ErrorActionPreference = 'Continue'
$gm = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$errs = $null
$tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm, [ref]$tok, [ref]$errs)
if ($errs) { Write-Host 'PARSE_ERRORS:'; $errs | ForEach-Object { $_.ToString() } } else { Write-Host 'PARSE_OK' }
# show around Save-LaptopHostKeyFingerprint / Acquire
$lines = Get-Content $gm
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Save-LaptopHostKeyFingerprint|function Acquire-TunnelPort|ACQUIRE_KEEP|function Get-ForeignTunnelPortSet|function Ensure-SessionTunnel') {
    Write-Host ("{0}: {1}" -f ($i+1), $lines[$i])
  }
}
# dump 560-720
Write-Host '=== DUMP 560-700 ==='
for ($i = 559; $i -lt 700 -and $i -lt $lines.Count; $i++) {
  Write-Host ("{0,4}|{1}" -f ($i+1), $lines[$i])
}
