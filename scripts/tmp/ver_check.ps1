function V($t){ $o=Join-Path $env:TEMP 'vv.txt'; $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$t,"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.e'); if(-not $p.WaitForExit(12000)){try{$p.Kill()}catch{};return 'TIMEOUT'}; ((Get-Content $o -Raw)+'').Trim() }
Write-Host ('Smart='+(V 'smart@192.168.210.240'))
Write-Host ('Sepidz='+(V 'sepidz@192.168.250.70'))
