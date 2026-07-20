$cmd='grep -n "Invoke-BundleDownload" /usr/local/share/claude-client/connect-update.ps1 | head -5; echo ---; sed -n "198,205p" /usr/local/share/claude-client/connect-update.ps1'
$o=Join-Path $env:TEMP 'c21b.txt'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','sepidz@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e')
$null=$p.WaitForExit(15000)
Get-Content $o
# local too
Write-Host '=== local ==='
Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'Invoke-BundleDownload' | Select-Object -First 5
Get-Content scripts\client\windows\connect-update.ps1 | Select-Object -Skip 197 -First 8
