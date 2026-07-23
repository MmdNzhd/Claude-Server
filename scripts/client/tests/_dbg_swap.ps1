$ErrorActionPreference = 'Stop'
$win = Get-Content 'scripts\client\windows\connect-update.ps1' -Raw
$m = [regex]::Match($win, "Write-UpdateFileLog\s+\(([^)]*swap_fail live=\`$Live[^)]*)\)\s+'ERROR'")
Write-Host ("found=" + $m.Success + " label=" + $m.Groups[1].Value)
if ($m.Success) {
  $start = $m.Index + $m.Length
  $wide = $win.Substring($start, [Math]::Min(1700, $win.Length-$start))
  Write-Host '--- WIDE WINDOW ---'
  Write-Host $wide
  Write-Host '--- CHECKS ---'
  Write-Host ("exit1=" + [bool]($wide -match 'exit\s+1\b'))
  Write-Host ("return_false=" + [bool]($wide -match 'return\s+\$false\b'))
  Write-Host ("return_true=" + [bool]($wide -match 'return\s+\$true\b'))
  Write-Host ("throw=" + [bool]($wide -match 'throw\b'))
}
