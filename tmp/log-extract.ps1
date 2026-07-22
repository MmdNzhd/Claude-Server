param([string]$Log,[string]$LineList)
$nums = $LineList -split ',' | ForEach-Object {[int]$_.Trim()}
$lines = Get-Content -LiteralPath $Log
foreach ($n in $nums) {
  $start = [Math]::Max(1, $n-15)
  $end = [Math]::Min($lines.Count, $n+5)
  Write-Output "===== CONTEXT $n (lines $start-$end) ====="
  for ($i=$start; $i -le $end; $i++) { Write-Output ("{0,5}|{1}" -f $i, $lines[$i-1]) }
}
