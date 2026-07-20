$p = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$lines = Get-Content $p
Write-Host "total_lines=$($lines.Count) bytes=$((Get-Item $p).Length)"
Write-Host "--- key events ---"
$pat = 'session start|STEP end|DECISION:|Connection dropped|TUNNEL_DROP|recover|LOG_SYNC|MOUNT|session_open|Opening|Ready|ORPHAN|STALE_FORWARD|port 2100|PERF\[|BOOTSTRAP|UPDATE'
$lines | Select-String -Pattern $pat | Select-Object -First 100 | ForEach-Object {
  $L = $_.Line
  if ($L.Length -gt 180) { $L.Substring(0,180) } else { $L }
}
Write-Host "--- count by level ---"
$lines | ForEach-Object {
  if ($_ -match '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]') { $Matches[1] }
} | Group-Object | Sort-Object Count -Descending | Format-Table Name, Count -AutoSize
Write-Host "--- first/last ---"
$lines[0]
$lines[-1]
Write-Host "--- LOG_SYNC ---"
$lines | Select-String 'LOG_SYNC' | Select-Object -First 20 | ForEach-Object { $_.Line }
