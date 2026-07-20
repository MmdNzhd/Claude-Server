$ErrorActionPreference = 'Continue'
Write-Host '=== Killing hung deploy/ssh ===' -ForegroundColor Yellow

# Kill stuck deploy script first
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'run-deploy-both|deploy-client-bundles|poll-deploy|check-deploy' } |
  ForEach-Object {
    Write-Host ("kill powershell PID=$($_.ProcessId)")
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

# Kill ssh to smart/sepidz that look stuck on sudo or version probes from our scripts
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object {
    $_.CommandLine -match '192\.168\.(210\.240|250\.70)' -and
    $_.CommandLine -match 'sudo|claude-client|connect-version|install-client-bundle|run-sepidz-bundle'
  } |
  ForEach-Object {
    Write-Host ("kill ssh PID=$($_.ProcessId)")
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

Start-Sleep -Seconds 2
$left = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match 'claude-client-bundle|install-client-bundle' })
Write-Host ("remaining_install_ssh=" + $left.Count)

Write-Host ''
Write-Host '=== Connectivity smoke (5s) ===' -ForegroundColor Cyan
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $job = Start-Job -ScriptBlock {
    param($target)
    & ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 $target "echo PONG; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
  } -ArgumentList $t
  if (Wait-Job $job -Timeout 12) {
    $r = Receive-Job $job
    Write-Host ("{0} => {1}" -f $t, ($r -join ' | '))
  } else {
    Write-Host ("{0} => TIMEOUT" -f $t)
    Stop-Job $job -Force -ErrorAction SilentlyContinue
  }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
}
