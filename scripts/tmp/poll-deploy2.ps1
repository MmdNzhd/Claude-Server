$ErrorActionPreference='Continue'
Write-Output ("time=" + (Get-Date -Format o))
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'run-deploy-both|deploy-client-bundles' })
Write-Output ("deploy_procs=" + $procs.Count)
$procs | ForEach-Object { "  PID=$($_.ProcessId) start=$($_.CreationDate)" }

# ssh processes
$sshs = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match '192.168.250.70|192.168.210.240|claude-client-bundle' })
Write-Output ("ssh_procs=" + $sshs.Count)
$sshs | ForEach-Object {
  $age = if ($_.CreationDate) { [int]((Get-Date) - [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate)).TotalSeconds } else { -1 }
  "  PID=$($_.ProcessId) age_s=$age CMD=$($_.CommandLine.Substring(0,[Math]::Min(140,$_.CommandLine.Length)))"
}

Write-Output '--- smart quick ---'
$sw = [Diagnostics.Stopwatch]::StartNew()
$sv = & ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 smart@192.168.210.240 "echo ok; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt" 2>&1
Write-Output ("smart_ms=$($sw.ElapsedMilliseconds) out=$sv")

Write-Output '--- sepidz quick ---'
$sw.Restart()
$zv = & ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 sepidz@192.168.250.70 "echo ok; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt" 2>&1
Write-Output ("sepidz_ms=$($sw.ElapsedMilliseconds) out=$zv exit=$LASTEXITCODE")
