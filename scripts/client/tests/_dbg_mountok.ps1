$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$m = [regex]::Match($win, '(?s)function Complete-PostTunnelRecovery\s*\{.*?^\}')
$fn = $m.Value
Write-Host ("fn_len=" + $fn.Length)
Write-Host ("has_TestProject=" + ($fn -match 'Test-ProjectMountHealthy|mountpoint'))
Write-Host ("has_REASSERT=" + ($fn -match 'RECOVERY_MOUNTOK_REASSERT|MOUNTOK_REASSERT'))
$reIdx = $fn.IndexOf('RECOVERY_MOUNTOK_REASSERT')
if ($reIdx -lt 0) { $reIdx = $fn.IndexOf('MOUNTOK_REASSERT') }
$endIdx = $fn.IndexOf('RECOVERY_END')
Write-Host ("reIdx=$reIdx endIdx=$endIdx")
# show all RECOVERY_ occurrences
[regex]::Matches($fn, 'RECOVERY_[A-Z_]+') | ForEach-Object {
  Write-Host ("@{0} {1}" -f $_.Index, $_.Value)
}
Write-Host '---FN---'
Write-Host $fn
