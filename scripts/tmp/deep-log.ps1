$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host ("LOG_BYTES=" + (Get-Item $log).Length)
Write-Host ("LOG_LINES=" + (Get-Content $log | Measure-Object -Line).Lines)

# All session starts today
Write-Host "`n=== ALL SESSION STARTS ==="
Select-String -Path $log -Pattern 'session start v|BOOTSTRAP:|MULTI_INSTANCE:|SINGLE_INSTANCE:' |
  ForEach-Object { $_.Line }

# Latest session id
$last = Select-String -Path $log -Pattern 'session start v' | Select-Object -Last 1
if ($last.Line -match '\[([a-f0-9]{12})\]') { $sid = $Matches[1] } else { throw 'no sid' }
if ($last.Line -match 'v(2026\d+\.\d+)') { $ver = $Matches[1] } else { $ver = '?' }
Write-Host "`n=== FOCUS sid=$sid ver=$ver ==="
Write-Host $last.Line

# Full timeline of important events for latest session
Write-Host "`n=== FULL TIMELINE (filtered) ==="
$pats = 'STEP begin|STEP end|ACQUIRE_|ENSURE_TUNNEL|PUSH_CONF|HOSTKEY|foreign|peer_live|MOUNT_|LAUNCH_|CONNECT_OK|SSH_END exit|PERF|skip_acquire|ACQUIRE_FAST|ACQUIRE_BATCH|Server setup|Loading projects|Opening Cursor|Verifying|Mounting|Syncing|session end|EXIT|FAIL '
Select-String -Path $log -Pattern "\[$sid\]" |
  Where-Object { $_.Line -match $pats } |
  ForEach-Object { $_.Line }

# Compute step durations table
Write-Host "`n=== STEP DURATIONS ==="
Select-String -Path $log -Pattern "\[$sid\].*STEP end:" |
  ForEach-Object { $_.Line }

# SSH timing histogram for this session
Write-Host "`n=== SSH_END ms distribution ==="
$msList = @()
Select-String -Path $log -Pattern "\[$sid\].*SSH_END exit=.*ms=(\d+)" |
  ForEach-Object {
    if ($_.Line -match 'ms=(\d+)') { $msList += [int]$Matches[1] }
  }
if ($msList.Count -gt 0) {
  $sorted = $msList | Sort-Object
  Write-Host ("count={0} sum={1} avg={2:N0} p50={3} p90={4} max={5}" -f `
    $msList.Count, ($msList | Measure-Object -Sum).Sum, ($msList | Measure-Object -Average).Average, `
    $sorted[[int]($sorted.Count*0.5)], $sorted[[Math]::Min($sorted.Count-1,[int]($sorted.Count*0.9))], ($msList | Measure-Object -Maximum).Maximum)
  Write-Host 'slow>=1500:'
  Select-String -Path $log -Pattern "\[$sid\].*SSH_END exit=.*ms=" |
    ForEach-Object {
      if ($_.Line -match 'ms=(\d+)' -and [int]$Matches[1] -ge 1500) { $_.Line.Substring(0, [Math]::Min(220, $_.Line.Length)) }
    }
}

# Wall clock: session start -> last STEP end Opening Cursor / SESSION_OPEN
Write-Host "`n=== WALL CLOCK ==="
$t0 = $null; $tCursor = $null; $tSetup = $null; $tMenu = $null
Select-String -Path $log -Pattern "\[$sid\]" | ForEach-Object {
  if ($_.Line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\]') {
    $ts = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
    if ($_.Line -match 'session start') { $t0 = $ts }
    if ($_.Line -match 'STEP end: Server setup') { $tSetup = $ts; if ($_.Line -match 'ms=(\d+)') { $setupMs = $Matches[1] } }
    if ($_.Line -match 'STEP end: Loading projects') { $tMenu = $ts }
    if ($_.Line -match 'STEP begin: Checking SSH' -or $_.Line -match 'STEP end: Checking SSH') { if (-not $script:tPick) { $script:tPick = $ts } }
    if ($_.Line -match 'STEP end: Opening Cursor') { $tCursor = $ts }
  }
}
if ($t0) {
  Write-Host ("session_start={0}" -f $t0.ToString('HH:mm:ss.fff'))
  if ($tSetup) { Write-Host ("server_setup_done={0} delta_from_start={1:N1}s setup_ms_logged={2}" -f $tSetup.ToString('HH:mm:ss.fff'), ($tSetup-$t0).TotalSeconds, $setupMs) }
  if ($tMenu) { Write-Host ("projects_loaded={0} delta={1:N1}s" -f $tMenu.ToString('HH:mm:ss.fff'), ($tMenu-$t0).TotalSeconds) }
  if ($script:tPick) { Write-Host ("after_user_pick~={0} idle_menu≈{1:N1}s" -f $script:tPick.ToString('HH:mm:ss.fff'), $(if($tMenu){($script:tPick-$tMenu).TotalSeconds}else{-1})) }
  if ($tCursor) { Write-Host ("cursor_open={0} total_wall={1:N1}s" -f $tCursor.ToString('HH:mm:ss.fff'), ($tCursor-$t0).TotalSeconds) }
}

# Compare last 3 sessions Server setup + ENSURE acquire counts
Write-Host "`n=== LAST 3 SESSIONS COMPARE ==="
$sids = @(Select-String -Path $log -Pattern 'session start v' | Select-Object -Last 3 | ForEach-Object {
  if ($_.Line -match '\[([a-f0-9]{12})\].*v(2026\d+\.\d+)') { [pscustomobject]@{Sid=$Matches[1]; Ver=$Matches[2]; Line=$_.Line} }
})
foreach ($s in $sids) {
  $setup = Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*STEP end: Server setup") | Select-Object -Last 1
  $ensures = @(Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*ENSURE_TUNNEL start"))
  $acquires = @(Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*(ACQUIRE_SKIP|ACQUIRE_FAST|Acquire)"))
  $skips = @(Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*skip_acquire"))
  $fast = @(Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*ACQUIRE_FAST"))
  $peer = @(Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*peer_live"))
  $foreign = @(Select-String -Path $log -Pattern ("\[" + $s.Sid + "\].*foreign"))
  Write-Host ("--- {0} v{1} ---" -f $s.Sid, $s.Ver)
  Write-Host ("  setup: {0}" -f $(if($setup){$setup.Line}else{'(none)'}))
  Write-Host ("  ENSURE_TUNNEL start count={0}" -f $ensures.Count)
  Write-Host ("  skip_acquire count={0} ACQUIRE_FAST count={1}" -f $skips.Count, $fast.Count)
  Write-Host ("  peer_live lines={0} foreign lines={1}" -f $peer.Count, $foreign.Count)
  foreach ($e in $ensures) { Write-Host ("  ENSURE: " + $e.Line.Substring(0,[Math]::Min(160,$e.Line.Length))) }
  foreach ($f in $fast) { Write-Host ("  FAST: " + $f.Line.Substring(0,[Math]::Min(180,$f.Line.Length))) }
}

# Is .13 even in the log yet?
Write-Host "`n=== VERSION IN LOG ==="
Select-String -Path $log -Pattern 'session start v20260721\.(1[123]|13)' | ForEach-Object { $_.Line }
Write-Host 'connect-version on desktop:'
Get-Content (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-version.txt') -Raw
Get-Content (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt') -Raw
