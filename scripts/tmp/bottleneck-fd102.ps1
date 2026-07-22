$f = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
$sid = 'fd102c09b242'
$lines = Select-String -Path $f -Pattern "\[$sid\]" | ForEach-Object { $_.Line }

Write-Host "=== STEP durations $sid ===" -ForegroundColor Cyan
$steps = @()
foreach ($l in $lines) {
  if ($l -match 'STEP end: (.+?) (ok|FAIL) ms=(\d+)') {
    $steps += [pscustomobject]@{ Step=$matches[1]; Ms=[int]$matches[3]; Line=$l.Substring(0,23) }
  }
}
$steps | Sort-Object Ms -Descending | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== SSH_END ms stats (session) ===" -ForegroundColor Cyan
$ms = @()
foreach ($l in $lines) {
  if ($l -match 'SSH_END exit=\d+ ms=(\d+)') { $ms += [int]$matches[1] }
}
if ($ms.Count) {
  $sorted = $ms | Sort-Object
  $sum = ($ms | Measure-Object -Sum).Sum
  $avg = [int]($sum / $ms.Count)
  $p50 = $sorted[[int]($sorted.Count*0.5)]
  $p95 = $sorted[[Math]::Min($sorted.Count-1, [int]($sorted.Count*0.95))]
  Write-Host ("count={0} min={1} avg={2} p50={3} p95={4} max={5} total_ssh_ms={6}" -f $ms.Count, $sorted[0], $avg, $p50, $p95, $sorted[-1], $sum)
}

Write-Host "`n=== LOG_SYNC during open ===" -ForegroundColor Cyan
$sync = @($lines | Where-Object { $_ -match 'LOG_SYNC' }).Count
Write-Host "LOG_SYNC lines=$sync"

Write-Host "`n=== AUTH db size ===" -ForegroundColor Cyan
$lines | Where-Object { $_ -match 'db_bytes=' } | Select-Object -First 3 | ForEach-Object { Write-Host $_ }

Write-Host "`n=== Biggest SSH_END ===" -ForegroundColor Cyan
$lines | Where-Object { $_ -match 'SSH_END exit=\d+ ms=(\d+)' } | ForEach-Object {
  if ($_ -match 'ms=(\d+)') { [pscustomobject]@{Ms=[int]$matches[1]; Line=$_} }
} | Sort-Object Ms -Descending | Select-Object -First 8 | ForEach-Object { Write-Host ("{0}  {1}" -f $_.Ms, $_.Line.Substring(0,[Math]::Min(180,$_.Line.Length))) }

# wall project path
$t0 = $null; $t1 = $null
foreach ($l in $lines) {
  if ($l -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})' -and $l -match 'STEP begin: Checking SSH') { $t0 = [datetime]::ParseExact($matches[1],'yyyy-MM-dd HH:mm:ss',$null) }
  if ($l -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})' -and $l -match 'DIAGNOSTIC REPORT \[SESSION_OPEN\]') { $t1 = [datetime]::ParseExact($matches[1],'yyyy-MM-dd HH:mm:ss',$null) }
}
if ($t0 -and $t1) { Write-Host ("`nWALL project->session_open: {0}s" -f [int]($t1-$t0).TotalSeconds) }
