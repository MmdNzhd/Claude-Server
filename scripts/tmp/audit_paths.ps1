$ErrorActionPreference='Continue'
$bad = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
Write-Host '=== Wrong folder currently running ==='
Write-Host ('ver=' + (Get-Content (Join-Path $bad 'connect-version.txt') -Raw -EA SilentlyContinue).Trim())
$cp = Get-Content (Join-Path $bad 'connect.ps1') -Raw
Write-Host ('has_sepidz_alias=' + ($cp -match 'claude-server-sepidz'))
Write-Host ('has_claude-server=' + [bool]($cp -match 'Alias\s*=\s*"claude-server"'))
Write-Host ('IP_250=' + [bool]($cp -match '192\.168\.250\.70'))
Write-Host ('IP_210=' + [bool]($cp -match '192\.168\.210\.240'))
Write-Host ('has_PERF_off=' + (Select-String -Path (Join-Path $bad 'connect-ui.ps1') -Pattern "CLAUDE_CONNECT_PERF_LOG -eq '1'" -SimpleMatch -Quiet))
Write-Host ('has_mutex=' + (Select-String -Path (Join-Path $bad 'connect-ui.ps1') -Pattern 'Enter-ConnectSingleInstance' -SimpleMatch -Quiet))

Write-Host ''
Write-Host '=== SSH config Host for sepidz ==='
$ssh = Join-Path $env:USERPROFILE '.ssh\config'
Select-String -Path $ssh -Pattern 'claude-server|250\.70|210\.240|Host |User ' |
  Select-Object -First 40 |
  ForEach-Object { $_.Line.Trim() }

Write-Host ''
Write-Host '=== Where server logs live (smart + sepidz accounts on 250.70) ==='
$cmd = @'
for u in sepidz smart; do
  echo USER=$u
  if [ -d /home/$u/.claude/logs ]; then ls -la /home/$u/.claude/logs/connect-*.log 2>/dev/null | tail -5; else echo no_logs_dir; fi
done
echo ---
# also check if smart home exists on sepidz box
getent passwd smart sepidz 2>/dev/null
'@
$out = Join-Path $env:TEMP 'loghomes.txt'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','sepidz@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
$null = $p.WaitForExit(20000)
Get-Content $out

Write-Host ''
Write-Host '=== Good folder ==='
$good = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows'
Write-Host ('ver=' + (Get-Content (Join-Path $good 'connect-version.txt') -Raw).Trim())
Write-Host ('PERF_off=' + (Select-String -Path (Join-Path $good 'connect-ui.ps1') -Pattern "CLAUDE_CONNECT_PERF_LOG -eq '1'" -SimpleMatch -Quiet))
Write-Host ('mutex=' + (Select-String -Path (Join-Path $good 'connect-ui.ps1') -Pattern 'Enter-ConnectSingleInstance' -SimpleMatch -Quiet))
