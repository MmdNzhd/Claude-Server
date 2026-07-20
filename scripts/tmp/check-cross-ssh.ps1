Write-Host "Laptop -> Sepidz:" -ForegroundColor Cyan
$p1 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.250.70','echo OK') -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\c1.out"
Get-Content "$env:TEMP\c1.out"; Write-Host "exit=$($p1.ExitCode)"

Write-Host "`nSmart server -> Sepidz (from Smart server):" -ForegroundColor Cyan
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=5','smart@192.168.210.240','ssh -o BatchMode=yes -o ConnectTimeout=5 smart@192.168.250.70 echo OK') -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\c2.out" -RedirectStandardError "$env:TEMP\c2.err"
Get-Content "$env:TEMP\c2.out" -ErrorAction SilentlyContinue
Get-Content "$env:TEMP\c2.err" -ErrorAction SilentlyContinue | Select-Object -First 3
Write-Host "exit=$($p2.ExitCode)"
