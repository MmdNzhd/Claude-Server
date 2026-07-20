$ErrorActionPreference='Continue'
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')

Write-Host '=== ALL connect.ps1 processes ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.ps1' } |
  ForEach-Object {
    Write-Host ("PID={0} {1}" -f $_.ProcessId, $_.CommandLine)
  }

Write-Host ''
Write-Host '=== session b25d17344291 full timeline (no PERF/TRACE) ==='
Select-String -Path $today -Pattern '\[b25d17344291\]' |
  Where-Object { $_.Line -notmatch '\[PERF|\[TRACE|\[DEBUG\].*PERF' } |
  ForEach-Object {
    $line = $_.Line
    if ($line.Length -gt 240) { $line = $line.Substring(0,240) + '...' }
    # only INFO/WARN/ERROR mostly
    if ($line -match '\[(INFO|WARN|ERROR)\]') { Write-Host $line }
  }

Write-Host ''
Write-Host '=== SSH timing for this session ==='
$ssh = Select-String -Path $today -Pattern '\[b25d17344291\].*SSH_END' | ForEach-Object {
  if ($_.Line -match 'ms=(\d+)') { [int]$Matches[1] }
}
if ($ssh) {
  Write-Host ('ssh_calls=' + $ssh.Count)
  Write-Host ('ssh_total_ms=' + ($ssh | Measure-Object -Sum).Sum)
  Write-Host ('ssh_avg_ms=' + [int](($ssh | Measure-Object -Average).Average))
  Write-Host ('ssh_max_ms=' + ($ssh | Measure-Object -Maximum).Maximum)
}

Write-Host ''
Write-Host '=== first/last timestamp this session ==='
$lines = Select-String -Path $today -Pattern '\[b25d17344291\]' | Select-Object -First 1 -Last 1
$all = @(Select-String -Path $today -Pattern '\[b25d17344291\]')
if ($all.Count -gt 0) {
  Write-Host ('first=' + $all[0].Line.Substring(0,30))
  Write-Host ('last =' + $all[-1].Line.Substring(0, [Math]::Min(200,$all[-1].Line.Length)))
  Write-Host ('line_count=' + $all.Count)
}

# folder version of running sepidz
$sepFolder = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
if (Test-Path (Join-Path $sepFolder 'connect-version.txt')) {
  Write-Host ('running_folder_ver=' + (Get-Content (Join-Path $sepFolder 'connect-version.txt') -Raw).Trim())
}
$good = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows'
if (Test-Path (Join-Path $good 'connect-version.txt')) {
  Write-Host ('good_folder_ver=' + (Get-Content (Join-Path $good 'connect-version.txt') -Raw).Trim())
}

Write-Host ''
Write-Host '=== last 8 INFO of session ==='
Select-String -Path $today -Pattern '\[b25d17344291\].*\[INFO\]' | Select-Object -Last 8 | ForEach-Object {
  $l=$_.Line; if($l.Length -gt 220){$l=$l.Substring(0,220)}; Write-Host $l
}
