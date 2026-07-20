$ErrorActionPreference='Continue'
Write-Output ("time=" + (Get-Date -Format o))
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'run-deploy-both|deploy-client-bundles' })
Write-Output ("deploy_procs=" + $procs.Count)
$procs | ForEach-Object { "  PID=$($_.ProcessId)" }

function Probe($t) {
  $out = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=3 $t "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt" 2>$null
  if ($LASTEXITCODE -ne 0) { return "FAIL_EXIT_$LASTEXITCODE" }
  return $out
}
Write-Output ("sepidz=" + (Probe 'sepidz@192.168.250.70'))
Write-Output ("smart=" + (Probe 'smart@192.168.210.240'))

# Look for open cmd windows for sudo
$cmds = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'Claude bundle install|sudo bash' })
Write-Output ("sudo_cmd_windows=" + $cmds.Count)
$cmds | ForEach-Object { "  " + $_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length)) }
