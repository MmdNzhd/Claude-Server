#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$day = Get-Date -Format 'yyyyMMdd'
$log = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-$day.log"
$idx = Join-Path $env:USERPROFILE '.config\claude-connect\logs\sessions.index'
Write-Host "=== LOG $log ==="
$fi = Get-Item $log
Write-Host ("size={0:N0} mtime={1}" -f $fi.Length, $fi.LastWriteTime)

$failTags = @{}
$errTags = @{}
$warnTags = @{}
$versions = @{}
$sessions = @{}
$multi = 0; $unhandled = 0; $sshQuote = 0; $pushFail = 0; $tunnelDrop = 0; $outdated = 0
$lines = 0
$lastFail = New-Object System.Collections.Generic.List[string]
$reader = [System.IO.StreamReader]::new($log)
try {
  while ($null -ne ($line = $reader.ReadLine())) {
    $lines++
    if ($line -match "Connect version[: ]+v?([0-9.]+)|Client v([0-9.]+)|ConnectVersion[=']([0-9.]+)|v(20260720\.[0-9]+)") {
      $v = $Matches[1]; if (-not $v) { $v = $Matches[2] }; if (-not $v) { $v = $Matches[3] }; if (-not $v) { $v = $Matches[4] }
      if ($v) { if (-not $versions.ContainsKey($v)) { $versions[$v]=0 }; $versions[$v]++ }
    }
    if ($line -match '\[(s?[0-9a-fA-F-]{6,})\]') {
      $sid = $Matches[1]
      if (-not $sessions.ContainsKey($sid)) { $sessions[$sid]=0 }
      $sessions[$sid]++
    }
    if ($line -match '\bFAIL\b') {
      $tag = 'FAIL'
      if ($line -match 'FAIL\s+([A-Z0-9_]+)') { $tag = $Matches[1] }
      if (-not $failTags.ContainsKey($tag)) { $failTags[$tag]=0 }
      $failTags[$tag]++
      if ($lastFail.Count -ge 50) { [void]$lastFail.RemoveAt(0) }
      [void]$lastFail.Add(($line.Substring(0, [Math]::Min(240, $line.Length))))
    }
    if ($line -match '\]\s*ERROR\b|\bERROR\b') {
      $k = 'ERROR'
      if ($line -match 'ERROR\s+([A-Za-z0-9_]+)') { $k = $Matches[1] }
      if (-not $errTags.ContainsKey($k)) { $errTags[$k]=0 }
      $errTags[$k]++
    }
    if ($line -match '\]\s*WARN\b|\bWARN\b') {
      $k = 'WARN'
      if ($line -match 'WARN\s+([A-Za-z0-9_./:-]+)') { $k = $Matches[1] }
      if (-not $warnTags.ContainsKey($k)) { $warnTags[$k]=0 }
      $warnTags[$k]++
    }
    if ($line -match 'SINGLE_INSTANCE|already running|Another Claude Connect') { $multi++ }
    if ($line -match 'UNHANDLED|UPDATE_UNHANDLED') { $unhandled++ }
    if ($line -match 'SSH_QUOTE') { $sshQuote++ }
    if ($line -match 'SERVER_SCRIPT_PUSH|SCRIPT_PUSH') { $pushFail++ }
    if ($line -match 'TUNNEL_DROP') { $tunnelDrop++ }
    if ($line -match 'OUTDATED') { $outdated++ }
  }
} finally { $reader.Close() }

Write-Host "lines=$lines"
Write-Host '--- VERSIONS ---'
$versions.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "{0} x {1}" -f $_.Value, $_.Key }
Write-Host ("--- SESSIONS unique={0} ---" -f $sessions.Count)
$sessions.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object { "{0} lines sid={1}" -f $_.Value, $_.Key }
Write-Host '--- FAIL tags ---'
$failTags.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "{0,5}  {1}" -f $_.Value, $_.Key }
Write-Host '--- ERROR top ---'
$errTags.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { "{0,5}  {1}" -f $_.Value, $_.Key }
Write-Host '--- WARN top ---'
$warnTags.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { "{0,5}  {1}" -f $_.Value, $_.Key }
Write-Host "--- COUNTERS multi=$multi unhandled=$unhandled sshQuote=$sshQuote push=$pushFail tunnelDrop=$tunnelDrop outdated=$outdated ---"
Write-Host '--- LAST FAIL LINES ---'
$lastFail | ForEach-Object { $_ }
Write-Host '=== sessions.index (tail) ==='
if (Test-Path $idx) { Get-Content $idx -Tail 40 }
Write-Host '=== LAST 60 LOG LINES ==='
Get-Content $log -Tail 60
