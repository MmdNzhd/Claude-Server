$ErrorActionPreference = 'Stop'
$u = Get-Content 'scripts\client\windows\connect-update.ps1' -Raw
# Find swap_fail context
$idx = $u.IndexOf('swap_fail')
while ($idx -ge 0) {
  $start = [Math]::Max(0, $idx - 200)
  $len = [Math]::Min(500, $u.Length - $start)
  Write-Host "==== swap_fail@$idx ===="
  Write-Host (($u.Substring($start, $len) -replace "[\r\n]+", "`n"))
  $idx = $u.IndexOf('swap_fail', $idx + 1)
}
foreach ($key in @('manifest_empty','manifest_zero','manifest_empty_or_unreachable','manifest_zero_files')) {
  $i = $u.IndexOf($key)
  Write-Host ("==== $key @$i ====")
  if ($i -ge 0) {
    Write-Host (($u.Substring([Math]::Max(0,$i-250), [Math]::Min(600,$u.Length-[Math]::Max(0,$i-250))) -replace "[\r\n]+", "`n"))
  }
}
