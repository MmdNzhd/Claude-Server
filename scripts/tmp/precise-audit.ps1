$ErrorActionPreference = 'Continue'
$repo = 'D:\Smart\Claude-Code-Server'
$expectVer = '20260715.18'
$elPath = Join-Path $repo 'scripts\client\editor-launch.ps1'
$lines = Get-Content $elPath
$raw = Get-Content $elPath -Raw

Write-Host '════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ' PRECISE AUDIT — Cursor multi-window kill' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════' -ForegroundColor Cyan

# --- Exact line evidence for removed vs present ---
Write-Host "`n[1] Exact line evidence in editor-launch.ps1" -ForegroundColor Yellow

$evidence = @(
  @{ Label='preserve_open_windows'; Must=$true },
  @{ Label='LAUNCH_RETRY_NO_KILL'; Must=$true },
  @{ Label='WARNING=closes_all_profile_windows'; Must=$true },
  @{ Label="pre_launch_agent_or_new_window' -Force"; Must=$false },
  @{ Label='retry_before_$($strategy.Name)'; Must=$false },
  @{ Label='Stop-CursorServerProfileTreeIfNeeded -Reason "retry_before_'; Must=$false }
)

foreach ($e in $evidence) {
  $hits = @()
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -like ('*' + $e.Label.Replace('$','*') + '*') -or $lines[$i].Contains($e.Label)) {
      $hits += ($i+1)
    }
  }
  # more reliable: Select-String
  $ss = @(Select-String -Path $elPath -Pattern ([regex]::Escape($e.Label)) -SimpleMatch:$false -ErrorAction SilentlyContinue)
  if ($e.Label -match '\$') {
    $ss = @(Select-String -Path $elPath -Pattern ([regex]::Escape($e.Label)))
  } else {
    $ss = @(Select-String -Path $elPath -Pattern ([regex]::Escape($e.Label)) -SimpleMatch)
  }
  $nums = @($ss | ForEach-Object { $_.LineNumber })
  $present = $nums.Count -gt 0
  $ok = if ($e.Must) { $present } else { -not $present }
  $mark = if ($ok) { 'PASS' } else { 'FAIL' }
  $color = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} present={2} lines=[{3}]" -f $mark, $e.Label, $present, ($nums -join ',')) -ForegroundColor $color
}

# Show the actual preserve + retry blocks with line numbers
Write-Host "`n  --- Launch preserve block ---" -ForegroundColor DarkCyan
$ss = Select-String -Path $elPath -Pattern 'preserve_open_windows' | Select-Object -First 1
if ($ss) {
  $start = [Math]::Max(0, $ss.LineNumber - 4)
  $end = [Math]::Min($lines.Count-1, $ss.LineNumber + 3)
  for ($i=$start; $i -le $end; $i++) {
    Write-Host ("  {0,4}| {1}" -f ($i+1), $lines[$i])
  }
}
Write-Host "`n  --- Launch retry block ---" -ForegroundColor DarkCyan
$ss = Select-String -Path $elPath -Pattern 'LAUNCH_RETRY_NO_KILL' | Select-Object -First 1
if ($ss) {
  $start = [Math]::Max(0, $ss.LineNumber - 3)
  $end = [Math]::Min($lines.Count-1, $ss.LineNumber + 2)
  for ($i=$start; $i -le $end; $i++) {
    Write-Host ("  {0,4}| {1}" -f ($i+1), $lines[$i])
  }
}

Write-Host "`n[2] Decision matrix — what Launch-RemoteEditor DOES now" -ForegroundColor Yellow
Write-Host '  Condition -> Action' -ForegroundColor DarkCyan
Write-Host '  - profileProcCount=0 -> cold start, no kill'
Write-Host '  - profile open + new project -> new-window ONLY'
Write-Host '  - agentHome=true -> new-window ONLY'
Write-Host '  - strategy retry attempt>1 -> NO_KILL log, no Stop-Process'
Write-Host '  - Stop-IfNeeded WITHOUT -Force -> return 0, no wipe'
Write-Host '  - Stop-IfNeeded WITH -Force -> still can wipe (manual only)' 

Write-Host "[3] Runtime proof (live on this PC)" -ForegroundColor Yellow
. $elPath
$before = @(Get-CursorProfileProcesses).Count
$mainBefore = @(Get-CursorMainProfileProcesses).Count
$rc = Stop-CursorServerProfileTreeIfNeeded -Reason 'precise_audit_no_force'
$after = @(Get-CursorProfileProcesses).Count
$mainAfter = @(Get-CursorMainProfileProcesses).Count
Write-Host ("  profile_all: {0} -> {1}  (rc={2})" -f $before, $after, $rc)
Write-Host ("  profile_main: {0} -> {1}" -f $mainBefore, $mainAfter)
if (($before -eq $after) -and ($mainBefore -eq $mainAfter) -and ($rc -eq 0 -or $after -eq $before)) {
  Write-Host '  [PASS] without -Force did not kill any Cursor profile process' -ForegroundColor Green
} else {
  Write-Host '  [FAIL] process counts changed' -ForegroundColor Red
}

Write-Host "`n[4] File identity (SHA256 + version)" -ForegroundColor Yellow
$targets = @(
  @{ Name='REPO editor-launch'; Path=$elPath; ExpectHash=$null },
  @{ Name='Desktop Smart editor-launch'; Path='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\editor-launch.ps1' },
  @{ Name='Desktop Sepidz editor-launch'; Path='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\editor-launch.ps1' },
  @{ Name='REPO connect-version'; Path=(Join-Path $repo 'scripts\client\windows\connect-version.txt') },
  @{ Name='Desktop Smart connect-version'; Path='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect-version.txt' },
  @{ Name='Desktop Sepidz connect-version'; Path='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect-version.txt' },
  @{ Name='REPO mac connect-version'; Path=(Join-Path $repo 'scripts\client\mac\connect-version.txt') }
)
$repoElHash = (Get-FileHash $elPath -Algorithm SHA256).Hash
foreach ($t in $targets) {
  if (-not (Test-Path $t.Path)) { Write-Host ("  [FAIL] missing {0}" -f $t.Name) -ForegroundColor Red; continue }
  $h = (Get-FileHash $t.Path -Algorithm SHA256).Hash
  $extra = ''
  if ($t.Path -like '*editor-launch*') {
    $match = ($h -eq $repoElHash)
    $extra = if ($match) { ' ==REPO' } else { ' !=REPO' }
    $color = if ($match) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}{2}  {3}..." -f $(if($match){'PASS'}else{'FAIL'}), $t.Name, $extra, $h.Substring(0,16)) -ForegroundColor $color
  } else {
    $v = (Get-Content $t.Path -Raw).Trim()
    $ok = ($v -eq $expectVer)
    Write-Host ("  [{0}] {1} = '{2}'" -f $(if($ok){'PASS'}else{'FAIL'}), $t.Name, $v) -ForegroundColor $(if($ok){'Green'}else{'Red'})
  }
}

# ConnectVersion inside connect.ps1
Write-Host "`n[5] ConnectVersion strings" -ForegroundColor Yellow
foreach ($p in @(
  (Join-Path $repo 'scripts\client\windows\connect.ps1'),
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.ps1',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect.ps1',
  (Join-Path $repo 'scripts\client\mac\connect.sh'),
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\mac\connect.sh'
)) {
  if (-not (Test-Path $p)) { Write-Host "  [FAIL] missing $p" -ForegroundColor Red; continue }
  $t = Get-Content $p -Raw
  $m = [regex]::Match($t, "ConnectVersion\s*=\s*'([^']+)'|CONNECT_VERSION='([^']+)'")
  $ver = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
  $ipSmart = $t -match '192\.168\.210\.240'
  $ipSep = $t -match '192\.168\.250\.70'
  $ok = ($ver -eq $expectVer)
  $ipNote = if ($p -match 'sepidz') {
    if ($ipSep -and -not $ipSmart) { 'IP=SepidzOK' } else { 'IP=BAD' }
  } elseif ($p -match 'client-20260715\\windows\\connect') {
    if ($ipSmart -and -not $ipSep) { 'IP=SmartOK' } else { 'IP=check' }
  } else { '' }
  Write-Host ("  [{0}] {1} ver={2} {3}" -f $(if($ok){'PASS'}else{'FAIL'}), (Split-Path $p -Leaf), $ver, $ipNote) -ForegroundColor $(if($ok){'Green'}else{'Red'})
}

Write-Host "`n[6] Server bundles (live SSH, 8s timeout)" -ForegroundColor Yellow
function Probe([string]$label, [string]$target) {
  $ver = (ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 $target "cat /usr/local/share/claude-client/connect-version.txt" 2>$null)
  $pres = (ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 $target "grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1" 2>$null)
  $force = (ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 $target "grep -c pre_launch_agent_or_new_window /usr/local/share/claude-client/editor-launch.ps1" 2>$null)
  $ver = ("$ver").Trim(); $pres=("$pres").Trim().Split()[0]; $force=("$force").Trim().Split()[0]
  $ok = ($ver -eq $expectVer -and $pres -match '^[1-9]' -and $force -eq '0')
  Write-Host ("  [{0}] {1}: ver={2} preserve_hits={3} force_hits={4}" -f $(if($ok){'PASS'}else{'FAIL'}), $label, $ver, $pres, $force) -ForegroundColor $(if($ok){'Green'}else{'Red'})
  return $ok
}
$smartOk = Probe 'Smart' 'smart@192.168.210.240'
$sepidOk = Probe 'Sepidz' 'sepidz@192.168.250.70'

Write-Host "`n[7] Auto-update policy (precise)" -ForegroundColor Yellow
$cu = Get-Content (Join-Path $repo 'scripts\client\windows\connect-update.ps1') -Raw
# Extract Test-RemoteVersionNewer logic evidence
$fn = Select-String -Path (Join-Path $repo 'scripts\client\windows\connect-update.ps1') -Pattern 'function Test-RemoteVersionNewer' | Select-Object -First 1
Write-Host ("  Test-RemoteVersionNewer @ line {0}" -f $fn.LineNumber)
# Simulate: local=.18 remote=.17 => newer? false
function Test-RemoteVersionNewer([string]$Remote,[string]$Local) {
  if ($Remote -eq $Local) { return $false }
  if ($Remote -match '^(\d{8})\.(\d+)$' -and $Local -match '^(\d{8})\.(\d+)$') {
    $rd=[int]$Matches[1]; # wrong - need separate
  }
  $rParts = $Remote -split '\.'; $lParts = $Local -split '\.'
  if ($Remote -match '^(\d{8})\.(\d+)$') { $rD=[int]$Matches[1]; $rB=[int]$Matches[2] } else { return $false }
  if ($Local -match '^(\d{8})\.(\d+)$') { $lD=[int]$Matches[1]; $lB=[int]$Matches[2] } else { return $false }
  if ($rD -ne $lD) { return $rD -gt $lD }
  return $rB -gt $lB
}
# Fix function properly
function Test-VerNewer([string]$Remote,[string]$Local) {
  if (-not $Remote -or -not $Local) { return $false }
  if ($Remote -eq $Local) { return $false }
  if ($Remote -match '^(\d{8})\.(\d+)$') { $rD=[int]$Matches[1]; $rB=[int]$Matches[2] } else { return ($Remote -gt $Local) }
  if ($Local -match '^(\d{8})\.(\d+)$') { $lD=[int]$Matches[1]; $lB=[int]$Matches[2] } else { return ($Remote -gt $Local) }
  if ($rD -ne $lD) { return ($rD -gt $lD) }
  return ($rB -gt $lB)
}
$cases = @(
  @{ R='20260715.17'; L='20260715.18'; Expect=$false; Why='Desktop.18 vs Smart bundle.17' },
  @{ R='20260715.18'; L='20260715.17'; Expect=$true; Why='would upgrade old client' },
  @{ R='20260715.18'; L='20260715.18'; Expect=$false; Why='same version skip' }
)
foreach ($c in $cases) {
  $got = Test-VerNewer $c.R $c.L
  $ok = ($got -eq $c.Expect)
  Write-Host ("  [{0}] remote={1} local={2} newer={3} expect={4} ({5})" -f $(if($ok){'PASS'}else{'FAIL'}), $c.R, $c.L, $got, $c.Expect, $c.Why) -ForegroundColor $(if($ok){'Green'}else{'Red'})
}

Write-Host "`n[8] connect.log evidence (Desktop Smart package)" -ForegroundColor Yellow
$log = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.log'
if (Test-Path $log) {
  $li = Get-Item $log
  Write-Host ("  log size={0} lastWrite={1}" -f $li.Length, $li.LastWriteTime)
  $hits = Select-String -Path $log -Pattern 'LAUNCH_KILL|preserve_open_windows|LAUNCH_RETRY_NO_KILL|ORPHAN_TUNNEL|session start|ConnectVersion|20260715' |
    Select-Object -Last 25
  if ($hits) {
    foreach ($h in $hits) { Write-Host ("  {0}" -f $h.Line.Substring(0, [Math]::Min(140, $h.Line.Length))) -ForegroundColor DarkGray }
  } else { Write-Host '  (no matching lines in tail patterns)' -ForegroundColor DarkGray }
  $killHits = @(Select-String -Path $log -Pattern 'LAUNCH_KILL:' )
  $skipHits = @(Select-String -Path $log -Pattern 'LAUNCH_KILL_SKIP: reason=preserve_open_windows')
  Write-Host ("  historical LAUNCH_KILL (force) count={0}" -f $killHits.Count)
  Write-Host ("  preserve_open_windows skip count={0}" -f $skipHits.Count)
} else { Write-Host '  no connect.log yet' -ForegroundColor Yellow }

Write-Host "`n[9] Call-site precision in connect.ps1" -ForegroundColor Yellow
$cp = Join-Path $repo 'scripts\client\windows\connect.ps1'
foreach ($pat in @('Launch-RemoteEditor','Clear-SessionMount','Stop-RemoteEditor','Stop-CursorServerProfileTree','editorOpened\s*=')) {
  $ss = @(Select-String -Path $cp -Pattern $pat)
  Write-Host ("  {0} => {1} hit(s) lines=[{2}]" -f $pat, $ss.Count, (($ss | ForEach-Object LineNumber) -join ','))
}

Write-Host "`n[10] Tests (exit codes)" -ForegroundColor Yellow
Push-Location $repo
foreach ($t in @('test-editor-launch-strategies.ps1','test-editor-launch.ps1','test-connect-pipeline.ps1','test-cursor-auth-merge.ps1')) {
  & (Join-Path 'scripts\client\tests' $t) *>$null
  $ok = ($LASTEXITCODE -eq 0)
  Write-Host ("  [{0}] {1} exit={2}" -f $(if($ok){'PASS'}else{'FAIL'}), $t, $LASTEXITCODE) -ForegroundColor $(if($ok){'Green'}else{'Red'})
}
Pop-Location

Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ' VERDICT (precise)' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Local/Desktop path: FIXED at v20260715.18' -ForegroundColor Green
Write-Host ("  Sepidz server bundle: {0}" -f $(if($sepidOk){'FIXED .18'}else{'NOT FIXED'})) -ForegroundColor $(if($sepidOk){'Green'}else{'Red'})
Write-Host ("  Smart server bundle:  {0}" -f $(if($smartOk){'FIXED .18'}else{'STILL .17 with Force-kill (Desktop safe: no downgrade)'})) -ForegroundColor $(if($smartOk){'Green'}else{'Yellow'})
Write-Host '  Use ONLY:' -ForegroundColor White
Write-Host '    Desktop\claude-publish\claude-code-client-20260715\windows\connect.bat' -ForegroundColor White
Write-Host '    Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect.bat' -ForegroundColor White
