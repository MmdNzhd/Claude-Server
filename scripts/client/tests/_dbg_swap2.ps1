$ErrorActionPreference = 'Stop'
$win = Get-Content 'scripts\client\windows\connect-update.ps1' -Raw
$m = [regex]::Match($win, "Write-UpdateFileLog\s+\(([^)]*swap_fail live=\`$Live[^)]*)\)\s+'ERROR'")
$start = $m.Index + $m.Length
# Find function end / return false after this
$fn = [regex]::Match($win.Substring($m.Index), '(?s)Write-UpdateFileLog\s+\(\"swap_fail live=\$Live.*?return\s+\$false')
Write-Host ("has_return_false_later=" + $fn.Success)
if ($fn.Success) {
  Write-Host ("distance=" + $fn.Length)
  Write-Host $fn.Value.Substring([Math]::Max(0,$fn.Value.Length-400))
}
# Show 2500 chars
Write-Host '---2500---'
Write-Host $win.Substring($start, [Math]::Min(2500, $win.Length-$start))
