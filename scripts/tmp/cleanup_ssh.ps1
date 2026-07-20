# Kill orphan reverse-tunnel / connect ssh flood; keep laptop-exec (usually to sepidz with specific patterns)
$killed=0
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | ForEach-Object {
  $cl = $_.CommandLine
  if (-not $cl) { return }
  $kill = $false
  if ($cl -match '-R\s+2100[0-9]:localhost:22') { $kill = $true }
  if ($cl -match 'claude-server-sepidz|claude-server\b' -and $cl -match 'timeout 45 bash') { $kill = $true }
  # flood of short BatchMode probes from hung connect
  if ($cl -match '192\.168\.250\.70' -and $cl -match 'BatchMode') { $kill = $true }
  if ($kill) {
    Write-Host ("KILL ssh pid={0} {1}" -f $_.ProcessId, $cl.Substring(0,[Math]::Min(140,$cl.Length)))
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
    $killed++
  }
}
Start-Sleep 1
Write-Host ("killed={0} ssh_left={1}" -f $killed, @(Get-Process ssh -EA SilentlyContinue).Count)
