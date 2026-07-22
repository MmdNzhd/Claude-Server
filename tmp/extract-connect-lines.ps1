param([string]$Path, [string]$LineList)
$nums = $LineList -split ',' | ForEach-Object { [int]$_.Trim() }
$lines = Get-Content -LiteralPath $Path
foreach ($r in $nums) {
  Write-Output "=== LINE $r ==="
  if ($r -ge 1 -and $r -le $lines.Count) { Write-Output $lines[$r-1] }
}
