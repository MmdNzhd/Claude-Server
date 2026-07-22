$ErrorActionPreference='Continue'
$now = Get-Date
$since = $now.AddMinutes(-30)
Write-Host ("NOW={0} SINCE={1}" -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $since.ToString('yyyy-MM-dd HH:mm:ss'))
Write-Host ""

function Parse-Ts([string]$line) {
  if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
    try { return [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch { return $null }
  }
  return $null
}

function Show-Recent($path, $label) {
  Write-Host ("========== {0} ==========" -f $label)
  Write-Host ("path={0}" -f $path)
  if (-not (Test-Path $path)) { Write-Host "MISSING"; Write-Host ""; return }
  $item = Get-Item $path
  Write-Host ("size={0:N0} mtime={1}" -f $item.Length, $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
  $recent = New-Object System.Collections.Generic.List[string]
  $warns = New-Object System.Collections.Generic.List[string]
  $errs = New-Object System.Collections.Generic.List[string]
  $notable = New-Object System.Collections.Generic.List[string]
  Get-Content -Path $path -Encoding UTF8 -EA SilentlyContinue | ForEach-Object {
    $line = $_
    $ts = Parse-Ts $line
    if ($null -eq $ts) { return }
    if ($ts -lt $since) { return }
    [void]$recent.Add($line)
    if ($line -match '\[ERROR\]|\[FATAL\]') { [void]$errs.Add($line) }
    elseif ($line -match '\[WARN\]') { [void]$warns.Add($line) }
    if ($line -match 'session start|session end|LAUNCH_KILL|LAUNCH_FAIL|PROC_START_FAIL|soft-stop|preserved_open|Updated to|bat_relaunch|CURSOR_PROXY|Opening Cursor|STEP end:|ENSURE_TUNNEL|elevated|ERROR|WARN|FAIL|fail |kill') {
      [void]$notable.Add($line)
    }
  }
  Write-Host ("recent_lines={0} warns={1} errors={2} notable={3}" -f $recent.Count, $warns.Count, $errs.Count, $notable.Count)
  Write-Host ""
  Write-Host "--- ERRORS ---"
  if ($errs.Count -eq 0) { Write-Host "(none)" } else { $errs | ForEach-Object { Write-Host $_ } }
  Write-Host ""
  Write-Host "--- WARNS ---"
  if ($warns.Count -eq 0) { Write-Host "(none)" } else { $warns | ForEach-Object { Write-Host $_ } }
  Write-Host ""
  Write-Host "--- NOTABLE ---"
  if ($notable.Count -eq 0) { Write-Host "(none)" } else { $notable | ForEach-Object { Write-Host $_ } }
  Write-Host ""
  Write-Host "--- FULL RECENT (truncated 220 chars) ---"
  $recent | ForEach-Object {
    $l = $_
    if ($l.Length -gt 220) { $l = $l.Substring(0,220) }
    Write-Host $l
  }
  Write-Host ""
}

$day = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Show-Recent $day 'LAPTOP_DAY_LOG'

Write-Host "========== OTHER LOG FILES (mtime last 30m) =========="
$dirs = @(
  (Join-Path $env:USERPROFILE '.config\claude-connect\logs'),
  (Join-Path $env:USERPROFILE '.claude\logs'),
  (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\logs')
)
foreach ($d in $dirs) {
  if (-not (Test-Path $d)) { continue }
  Get-ChildItem -Path $d -File -Recurse -EA SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $since } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 50 |
    ForEach-Object {
      Write-Host ("{0}  {1,10:N0}  {2}" -f $_.LastWriteTime.ToString('HH:mm:ss'), $_.Length, $_.FullName)
    }
}

Write-Host ""
Write-Host "========== DIAG FILE =========="
$diag = Join-Path $env:USERPROFILE '.claude\logs\laptop-ssh-diag-latest.txt'
if (Test-Path $diag) {
  $di = Get-Item $diag
  Write-Host ("diag mtime={0} size={1}" -f $di.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $di.Length)
  if ($di.LastWriteTime -ge $since) {
    Get-Content $diag -Tail 80 -EA SilentlyContinue | ForEach-Object { Write-Host $_ }
  } else {
    Write-Host "diag older than 30m - skip body"
  }
} else {
  Write-Host "no laptop-ssh-diag-latest.txt"
}

Write-Host ""
Write-Host "========== CURSOR PROFILE LOG ERRORS =========="
$cursorLogRoot = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\logs'
if (Test-Path $cursorLogRoot) {
  $latest = Get-ChildItem $cursorLogRoot -Directory -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) {
    Write-Host ("dir={0}" -f $latest.FullName)
    Get-ChildItem $latest.FullName -File -Recurse -EA SilentlyContinue |
      Where-Object { $_.LastWriteTime -ge $since } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 20 |
      ForEach-Object {
        Write-Host ("--- {0} mtime={1} size={2} ---" -f $_.Name, $_.LastWriteTime.ToString('HH:mm:ss'), $_.Length)
        $tail = @(Get-Content $_.FullName -Tail 80 -EA SilentlyContinue)
        $bad = @($tail | Where-Object { $_ -match 'error|Error|ERROR|fail|FAIL|ECONN|ENOTFOUND|timeout|proxy|Proxy|killed|EPERM|EACCES' })
        if ($bad.Count -gt 0) { $bad | Select-Object -Last 20 | ForEach-Object { Write-Host $_ } }
        else { Write-Host "(no error-ish in last 80 lines)" }
      }
  }
}

Write-Host ""
Write-Host "SCAN_DONE"
