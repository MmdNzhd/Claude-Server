$ErrorActionPreference='Continue'
Write-Host '=== Running connect details ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.ps1' } |
  ForEach-Object {
    Write-Host ("PID=" + $_.ProcessId)
    Write-Host ("  CMD=" + $_.CommandLine)
    Write-Host ("  Parent=" + $_.ParentProcessId)
  }

Write-Host ''
Write-Host '=== Local log: last session start / version lines ==='
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
Select-String -Path $today -Pattern 'session start|ConnectVersion|SINGLE_INSTANCE|BOOTSTRAP|v2026|UPDATE:|False' |
  Select-Object -Last 40 |
  ForEach-Object { $_.Line }

Write-Host ''
Write-Host '=== Count False / PERF in last 2000 lines ==='
$tail = Get-Content $today -Tail 2000
Write-Host ('False_lines=' + @($tail | Where-Object { $_ -eq 'False' -or $_ -match '^False$' }).Count)
Write-Host ('PERF_lines=' + @($tail | Where-Object { $_ -match 'PERF\[' }).Count)
Write-Host ('TUNNEL_SYNC_TRACE=' + @($tail | Where-Object { $_ -match 'TUNNEL_SYNC' }).Count)

Write-Host ''
Write-Host '=== Server log via ssh ==='
$day = Get-Date -Format 'yyyyMMdd'
$cmd = "ls -la ~/.claude/logs/connect-*.log 2>/dev/null | tail -8; echo ====; if [ -f ~/.claude/logs/connect-$day.log ]; then wc -c ~/.claude/logs/connect-$day.log; echo ----; tail -n 15 ~/.claude/logs/connect-$day.log; else echo NO_FILE_connect-$day.log; ls ~/.claude/logs/ | tail -10; fi"
$out = Join-Path $env:TEMP 'slog2.txt'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','sepidz@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
$null = $p.WaitForExit(20000)
Get-Content $out

Write-Host ''
Write-Host '=== Correct launch path ==='
$good = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows\connect.bat'
Write-Host ('EXISTS=' + (Test-Path $good) + ' PATH=' + $good)
if (Test-Path $good) {
  Write-Host ('bat_has_BOOTSTRAP=' + (Select-String -Path $good -Pattern 'BOOTSTRAP' -Quiet))
  Write-Host ('sibling_ver=' + (Get-Content (Join-Path (Split-Path $good) 'connect-version.txt') -Raw).Trim())
}
