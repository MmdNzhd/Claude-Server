$root='D:\Smart\Claude-Code-Server'
Write-Host '=== Get-ServerEndpoint in connect-update ==='
Get-Content "$root\scripts\client\windows\connect-update.ps1" | Select-Object -Skip 55 -First 40 | ForEach-Object { $_ }
Write-Host '=== how connect.ps1 sets server ==='
Select-String -Path "$root\scripts\client\windows\connect.ps1" -Pattern 'ServerIp|SERVER_IP|250\.70|210\.240|claude-server|Get-ServerEndpoint' |
  Select-Object -First 30 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== sepidz live connect.ps1 IP/version ==='
$o=[IO.Path]::GetTempFileName()
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10','sepidz@192.168.250.70','python3 -c "import re;t=open(\"/usr/local/share/claude-client/connect.ps1\",encoding=\"utf-8\",errors=\"replace\").read();print(re.findall(r\"ConnectVersion\\s*=\\s*''([^'']+)''\",t)[:1]);print(sorted(set(re.findall(r\"192\\.168\\.\\d+\\.\\d+\",t))))"') -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
[void]$p.WaitForExit(20000)
Write-Host ((Get-Content $o -Raw)+'')
Write-Host ((Get-Content "$o.err" -Raw -EA SilentlyContinue)+'')
