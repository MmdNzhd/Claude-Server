$ErrorActionPreference='Continue'
# Wait up to ~8 min for publish runner
$deadline = (Get-Date).AddMinutes(8)
while ((Get-Date) -lt $deadline) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -match 'run-full-publish|publish\.ps1|deploy-client-bundles|deploy-smart') }
  if (-not $procs) {
    Write-Host 'NO_PUBLISH_PROCS'
    break
  }
  Write-Host ("still running: " + (($procs | ForEach-Object { $_.ProcessId }) -join ','))
  Start-Sleep -Seconds 15
}
Write-Host '--- remote versions ---'
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  $v = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $t "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
  Write-Host "$t => [$v]"
}
Write-Host '--- pack markers ---'
$pack = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
Select-String -Path (Join-Path $pack 'git-mode.ps1') -Pattern 'nc -w 2|banner_miss_tcp_open|Reattach BEFORE|Positive cache' |
  ForEach-Object { $_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)) }
Select-String -Path (Join-Path $pack 'connect.ps1') -Pattern 'tunnelSyncOk|ConnectVersion' |
  Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }
Select-String -Path (Join-Path $pack 'connect-diagnostic.ps1') -Pattern 'tunnelEffectivelyUp' |
  Select-Object -First 2 | ForEach-Object { $_.Line.Trim() }
Get-Content (Join-Path $pack 'connect-version.txt')
