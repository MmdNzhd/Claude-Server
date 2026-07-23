$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260722.log'
$sid = 'd98967c3e2ab'
Write-Output "==== SESSION $sid LINES (boot+auth+steps) ===="
Select-String -LiteralPath $log -Pattern $sid |
  Where-Object { $_.Line -match 'STEP end|CONNECT_VERSION|AUTH|need_mount|ACQUIRE|PROC_START|SESSION_|WARN|ERROR|Mounting|Opening Cursor|Server setup|golden|personal_cursor|elevated' } |
  ForEach-Object { $_.Line }
Write-Output '==== SSH_END ms for session ===='
$ms = Select-String -LiteralPath $log -Pattern ("\[" + $sid + "\].*SSH_END") |
  ForEach-Object { if ($_.Line -match 'ms=(\d+)') { [int]$Matches[1] } }
if ($ms) {
  $sorted = $ms | Sort-Object
  $n = $sorted.Count
  $sum = ($sorted | Measure-Object -Sum).Sum
  Write-Output ("n={0} avg={1:n0} p50={2} p90={3} max={4} gt1s={5} gt3s={6}" -f $n, ($sum/$n), $sorted[[int]($n*0.5)], $sorted[[int]($n*0.9)], $sorted[-1], @($sorted | Where-Object { $_ -gt 1000 }).Count, @($sorted | Where-Object { $_ -gt 3000 }).Count)
}
Write-Output '==== banner poll count last 10 min ===='
Select-String -LiteralPath $log -Pattern 'TUNNEL_BANNER_BEGIN' |
  Select-Object -Last 5 | ForEach-Object { $_.Line }
