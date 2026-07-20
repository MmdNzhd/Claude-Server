$Server = 'sepidz@192.168.250.70'
$pw = 'sepidz'
$outFile = Join-Path $env:TEMP 'sudo-test.out'
$errFile = Join-Path $env:TEMP 'sudo-test.err'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8',$Server,"bash -lc ""echo '$pw' | sudo -S whoami 2>&1""") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
Get-Content $outFile -ErrorAction SilentlyContinue
Get-Content $errFile -ErrorAction SilentlyContinue
Write-Host "exit=$($p.ExitCode)"
