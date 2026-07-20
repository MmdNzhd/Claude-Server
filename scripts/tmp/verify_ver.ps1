$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$out=Join-Path $env:TEMP 'ver.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70','cat /usr/local/share/claude-client/connect-version.txt; ls /usr/local/share/claude-client | head') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(30000)
Write-Host 'SEPIDZ_LIVE=' -NoNewline; Get-Content $out -Raw
# smart frozen check if reachable
try {
  $o2=Join-Path $env:TEMP 'ver2.out'
  $p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $o2 -RedirectStandardError ($o2+'.err')
  if($p2.WaitForExit(20000)){ Write-Host 'SMART_LIVE=' -NoNewline; Get-Content $o2 -Raw }
} catch {}
