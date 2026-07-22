$ErrorActionPreference='Continue'
$desk = Join-Path $env:USERPROFILE 'Desktop'
$win = Join-Path $desk 'claude-publish\claude-code-client\windows'
Write-Host '=== windows folder ==='
if (Test-Path $win) {
  Get-ChildItem $win | Sort-Object Name | ForEach-Object {
    '{0,-40} {1,12}' -f $_.Name, $_.Length
  }
} else { Write-Host 'MISSING' }

Write-Host ''
Write-Host '=== Desktop EXE ==='
Get-ChildItem $desk -Filter 'Claude-Connect*.exe' | ForEach-Object {
  '{0} {1} {2}' -f $_.Name, $_.Length, $_.LastWriteTime
}

Write-Host ''
Write-Host '=== connect-version ==='
@('Claude-Connect\connect-version.txt','claude-publish\claude-code-client\windows\connect-version.txt') | ForEach-Object {
  $p = Join-Path $desk $_
  if (Test-Path $p) { Write-Host ("{0} = {1}" -f $_, (Get-Content $p -Raw).Trim()) }
}

Write-Host ''
Write-Host '=== recent day log ==='
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$day = Get-Date -Format 'yyyyMMdd'
$log = Join-Path $logDir ("connect-{0}.log" -f $day)
if (-not (Test-Path $log)) {
  $newest = Get-ChildItem $logDir -Filter 'connect-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($newest) { $log = $newest.FullName }
}
Write-Host ("log={0}" -f $log)
if ($log -and (Test-Path $log)) {
  Get-Content $log -Tail 250 | Where-Object {
    $_ -match 'UPDATE|exe_only|FAIL|ERROR|OUTDATED|BOOTSTRAP|available|applied|drift|scp|manifest|fallback|heal|relaunch'
  } | Select-Object -Last 100
} else {
  Write-Host 'no log'
}

Write-Host ''
Write-Host '=== update log if any ==='
$upd = Join-Path $env:TEMP 'claude-connect-update*.log'
Get-ChildItem (Join-Path $env:USERPROFILE '.config\claude-connect') -Recurse -Filter '*update*' -ErrorAction SilentlyContinue | Select-Object -First 10 FullName, Length, LastWriteTime
