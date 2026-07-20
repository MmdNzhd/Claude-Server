# Show TUNNEL_SYNC and PERF sections in sh files
$gm = Get-Content scripts\client\git-mode.sh -Raw
$ui = Get-Content scripts\client\connect-ui.sh -Raw
$mac = Get-Content scripts\client\mac\connect.sh -Raw

Write-Host "=== git-mode.sh: TUNNEL_SYNC lines with context ==="
$lines = Get-Content scripts\client\git-mode.sh
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'TUNNEL_SYNC|last_tunnel_sync|TUNNEL_SYNC_TRACE') {
    $start = [Math]::Max(0,$i-3); $end=[Math]::Min($lines.Count-1,$i+2)
    for ($j=$start;$j -le $end;$j++) { Write-Host ("{0,4}|{1}" -f ($j+1), $lines[$j]) }
    Write-Host '---'
  }
}

Write-Host "=== connect-ui.sh: should_log_perf / PERF ==="
Select-String -Path scripts\client\connect-ui.sh -Pattern 'PERF|should_log|cim_query' | ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Host "=== mac connect.sh session loop sleep ==="
Select-String -Path scripts\client\mac\connect.sh -Pattern 'sleep |editor_check|PERF|cim' | Select-Object -First 25 | ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Host "=== windows Should-LogPerf ==="
Select-String -Path scripts\client\connect-ui.ps1 -Pattern 'Should-LogPerf|PERF\[' -Context 0,5 | Select-Object -First 20 | ForEach-Object { $_.Line }
