$ErrorActionPreference='Continue'
Write-Host '=== SSH hosts matching claude/sepidz/250 ==='
$ssh = Join-Path $env:USERPROFILE '.ssh\config'
Get-Content $ssh | Select-String -Pattern 'claude|250\.70|sepidz|Host ' -Context 0,3 |
  ForEach-Object { $_.Line; if ($_.Context.PostContext) { $_.Context.PostContext | ForEach-Object { '  ' + $_ } } } |
  Select-Object -First 80

Write-Host ''
Write-Host '=== Sync remote path logic in connect-ui.ps1 ==='
Select-String -Path 'scripts\client\connect-ui.ps1' -Pattern 'Sync-ConnectLogToServer|remote|claude/logs|mkdir|scp|HOME' |
  Select-Object -First 50 |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Host ''
Write-Host '=== Probe log dirs on 250.70 as smart ==='
$cmd = 'ls -la /home/smart/.claude 2>&1; ls -la /home/sepidz/.claude 2>&1; find /home/smart /home/sepidz -maxdepth 3 -name "connect-*.log" 2>/dev/null | head'
$out = Join-Path $env:TEMP 'logfind.txt'
# try as smart@250.70
foreach ($t in @('smart@192.168.250.70','sepidz@192.168.250.70')) {
  Write-Host ("TARGET=" + $t)
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$t,$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
  if (-not $p.WaitForExit(12000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT' }
  else { Get-Content $out -EA SilentlyContinue; Get-Content ($out+'.err') -EA SilentlyContinue | Select-Object -First 5 }
}
