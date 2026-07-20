$ErrorActionPreference='Continue'
# Check if powershell deploy still running
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'run-deploy-both|deploy-client-bundles' } |
  ForEach-Object { "PID=$($_.ProcessId) CMD=$($_.CommandLine.Substring(0,[Math]::Min(120,$_.CommandLine.Length)))" }
Write-Output '--- remote versions ---'
foreach ($t in @('sepidz@192.168.250.70','smart@192.168.210.240')) {
  $v = ssh -o BatchMode=yes -o ConnectTimeout=8 $t "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null"
  Write-Output ("{0} => {1}" -f $t, $v)
}
