$Server = 'sepidz@192.168.250.70'
$outFile = Join-Path $env:TEMP 'sudo-b64.out'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10',$Server,'bash -lc "base64 -d <<< c2VwaWR6QEFkbWlu | sudo -S whoami 2>&1"') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile
Get-Content $outFile
Write-Host "exit=$($p.ExitCode)"
