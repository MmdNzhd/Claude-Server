$p = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-20260721.log"
Write-Host '==== ALL CLEAR events ===='
Select-String -Path $p -Pattern 'CURSOR_PROXY_CLEAR' | ForEach-Object { $_.Line }

Write-Host ''
Write-Host '==== Lines for session 3db7e5c48210 (first 80) ===='
$lines = Select-String -Path $p -Pattern '\[3db7e5c48210\]' | ForEach-Object { $_.Line }
Write-Host ("count=" + $lines.Count)
$lines | Select-Object -First 80

Write-Host ''
Write-Host '==== 40 lines before CLEAR timestamp 18:44:29 ===='
$all = [System.IO.File]::ReadAllLines($p)
for ($i=0; $i -lt $all.Length; $i++) {
  if ($all[$i] -match '18:44:29\.\d+\].*CURSOR_PROXY_CLEAR: removed') {
    $s = [Math]::Max(0,$i-50); $e=[Math]::Min($all.Length-1,$i+15)
    for ($j=$s; $j -le $e; $j++) { $all[$j] }
    break
  }
}
