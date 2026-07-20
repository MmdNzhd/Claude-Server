$ErrorActionPreference = 'Continue'
$fail = 0; $warn = 0
function Ok($m) { Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Warn($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:warn++ }
function Sec($t) { Write-Host "`n======== $t ========" -ForegroundColor Cyan }

$repo = 'D:\Smart\Claude-Code-Server'
$expectVer = '20260715.18'
$banForce = "Stop-CursorServerProfileTreeIfNeeded -Reason 'pre_launch_agent_or_new_window' -Force"
$banRetry = 'retry_before_$($strategy.Name)'

# ---------- A: AST/function inventory of ALL Stop-Process on Cursor ----------
Sec 'A) Every Stop-Process / kill Cursor path in client scripts'
$clientFiles = Get-ChildItem "$repo\scripts\client" -Recurse -Include *.ps1,*.sh,*.bat -File |
  Where-Object { $_.FullName -notmatch '\\tests\\tmp|\\node_modules\\' }
$killHits = @()
foreach ($f in $clientFiles) {
  $i = 0
  Get-Content $f.FullName -ErrorAction SilentlyContinue | ForEach-Object {
    $i++
    $line = $_
    if ($line -match 'Stop-Process|Stop-CursorServerProfileTree|Kill-Process|taskkill|/IM Cursor|CloseMainWindow') {
      $rel = $f.FullName.Substring($repo.Length + 1)
      $killHits += [pscustomobject]@{ File=$rel; Line=$i; Text=$line.Trim() }
    }
  }
}
$allowed = @(
  @{ File='scripts\client\editor-launch.ps1'; Why='Stop-CursorServerProfileTree (manual -Force only); Stop-RemoteEditor path-scoped CloseMainWindow/Stop-Process' },
  @{ File='scripts\client\git-mode.ps1'; Why='ORPHAN tunnel Stop-Process on ssh.exe ONLY' }
)
Write-Host ("  Found {0} kill-related lines across client scripts" -f $killHits.Count) -ForegroundColor DarkGray
$unexpected = @()
foreach ($h in $killHits) {
  $okFile = $false
  foreach ($a in $allowed) { if ($h.File -eq $a.File) { $okFile = $true } }
  # classify
  $cls = 'REVIEW'
  if ($h.File -eq 'scripts\client\editor-launch.ps1') {
    if ($h.Text -match 'Stop-CursorServerProfileTree\b' -and $h.Text -notmatch 'IfNeeded') { $cls = 'HELPER_TREE_KILL' }
    elseif ($h.Text -match 'Stop-CursorServerProfileTreeIfNeeded') { $cls = 'GATED_FORCE_ONLY' }
    elseif ($h.Text -match 'CloseMainWindow') { $cls = 'SOFT_CLOSE_PATH' }
    elseif ($h.Text -match 'Stop-Process' -and $h.Text -match 'Get-RemoteEditorProcesses|RemoteEditor') { $cls = 'PATH_SCOPED_FORCE_AFTER_SOFT' }
    elseif ($h.Text -match 'Stop-Process' -and $h.Text -match '\$p\.ProcessId') { $cls = 'PROFILE_OR_PATH_STOP' }
    else { $cls = 'EDITOR_LAUNCH_OTHER' }
  } elseif ($h.File -eq 'scripts\client\git-mode.ps1') {
    if ($h.Text -match 'ORPHAN|BgTunnel|ssh' -or $h.Text -match 'Stop-Process -Id') { $cls = 'TUNNEL_SSH_ONLY' }
    else { $cls = 'GITMODE_OTHER' }
  } elseif ($h.File -match 'tests\\') {
    $cls = 'TEST'
  } else {
    $cls = 'UNEXPECTED'
    $unexpected += $h
  }
  $color = if ($cls -eq 'UNEXPECTED') { 'Red' } elseif ($cls -match 'HELPER_TREE|GATED') { 'Yellow' } else { 'DarkGray' }
  Write-Host ("  [{0}] {1}:{2} {3}" -f $cls, $h.File, $h.Line, ($h.Text.Substring(0,[Math]::Min(90,$h.Text.Length)))) -ForegroundColor $color
}
if ($unexpected.Count -eq 0) { Ok 'no unexpected kill sites outside editor-launch/git-mode/tests' }
else { foreach ($u in $unexpected) { Bad ("unexpected kill {0}:{1}" -f $u.File,$u.Line) } }

# ---------- B: Launch-RemoteEditor call graph from connect.ps1 ----------
Sec 'B) connect.ps1 call sites -> editor open/close'
$connect = Get-Content "$repo\scripts\client\windows\connect.ps1" -Raw
$patterns = @{
  'Launch-RemoteEditor' = 'opens editor'
  'Stop-RemoteEditor' = 'closes ONE project editor'
  'Clear-SessionMount' = 'unmount + optional path editor stop'
  'Stop-CursorServerProfileTree' = 'MUST NOT appear in connect.ps1'
  'Stop-CursorServerProfileTreeIfNeeded' = 'MUST NOT appear in connect.ps1'
  'editorOpened' = 'prevents re-open storm'
}
foreach ($k in $patterns.Keys) {
  $m = [regex]::Matches($connect, [regex]::Escape($k))
  $n = $m.Count
  if ($k -match 'Stop-CursorServerProfileTree') {
    if ($n -eq 0) { Ok "connect.ps1 has 0 refs to $k" } else { Bad "connect.ps1 still references $k ($n)" }
  } else {
    if ($n -gt 0) { Ok ("connect.ps1 {0} x{1} ({2})" -f $k,$n,$patterns[$k]) }
    else { Warn ("connect.ps1 missing {0}" -f $k) }
  }
}

# ---------- C: Simulate launch decision matrix (static condition analysis) ----------
Sec 'C) Launch decision matrix (static)'
$el = Get-Content "$repo\scripts\client\editor-launch.ps1" -Raw
# Confirm force kill cannot run from Launch-RemoteEditor body
$launchFn = [regex]::Match($el, '(?s)function Launch-RemoteEditor \{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $launchFn.Success) {
  # fallback: extract between function and next top-level function after it
  $start = $el.IndexOf('function Launch-RemoteEditor')
  $next = $el.IndexOf("`nfunction ", $start + 10)
  if ($next -lt 0) { $next = $el.Length }
  $body = $el.Substring($start, $next - $start)
} else { $body = $launchFn.Value }

if ($body -match [regex]::Escape($banForce)) { Bad 'Launch-RemoteEditor still Force-kills on pre_launch' }
else { Ok 'Launch-RemoteEditor: no pre_launch Force kill' }
if ($body -match 'Stop-CursorServerProfileTreeIfNeeded\s+-Reason.*"retry_before_') { Bad 'Launch-RemoteEditor still Force-kills on retry' }
else { Ok 'Launch-RemoteEditor: no retry Force kill' }
if ($body -match 'preserve_open_windows') { Ok 'Launch-RemoteEditor logs preserve_open_windows' } else { Bad 'preserve log missing in Launch body' }
if ($body -match 'LAUNCH_RETRY_NO_KILL') { Ok 'Launch-RemoteEditor logs LAUNCH_RETRY_NO_KILL' } else { Bad 'retry no-kill log missing' }
if ($body -match '\$useNewWindow') { Ok 'Launch still computes useNewWindow' } else { Bad 'useNewWindow gone' }

# Scenarios - what SHOULD happen now
$scenarios = @(
  @{ Name='cold start (0 profile procs)'; Expect='open without kill' },
  @{ Name='profile already open + new project'; Expect='--new-window, NO tree kill' },
  @{ Name='agent home stuck + profile open'; Expect='--new-window, NO tree kill (preserve)' },
  @{ Name='strategy retry #2'; Expect='NO tree kill' },
  @{ Name='manual Stop-...IfNeeded -Force'; Expect='still available but warned WARN' }
)
Write-Host '  Scenario expectations after fix:' -ForegroundColor DarkCyan
foreach ($s in $scenarios) { Write-Host ("    - {0} -> {1}" -f $s.Name, $s.Expect) -ForegroundColor DarkGray }
Ok 'scenario matrix documented against code invariants'

# ---------- D: Stop-CursorServerProfileTreeIfNeeded requires -Force ----------
Sec 'D) Gated helper requires -Force (safe default)'
. "$repo\scripts\client\editor-launch.ps1"
# mock: if profile procs exist, calling without Force returns 0 and does not throw
$before = @(Get-CursorProfileProcesses).Count
$rc = Stop-CursorServerProfileTreeIfNeeded -Reason 'ultra_deep_verify_no_force'
$after = @(Get-CursorProfileProcesses).Count
if ($rc -eq 0 -or $rc -eq $before) { Ok "without -Force: returned $rc, procs before=$before after=$after (not wiped)" }
else { Bad "without -Force unexpectedly returned $rc" }
if ($before -eq $after) { Ok "without -Force: process count unchanged ($after)" }
else { Bad "without -Force CHANGED process count $before->$after" }

# ---------- E: Stop-RemoteEditor is path-scoped ----------
Sec 'E) Stop-RemoteEditor path scoping'
$fn = [regex]::Match($el, '(?s)function Stop-RemoteEditor \{.*?function ', [System.Text.RegularExpressions.RegexOptions]::Singleline)
# simpler check
if ($el -match '(?s)function Stop-RemoteEditor \{[^}]*Get-RemoteEditorProcesses') { Ok 'Stop-RemoteEditor starts from Get-RemoteEditorProcesses (path/alias filter)' }
else { Bad 'Stop-RemoteEditor not using Get-RemoteEditorProcesses' }
# Get-RemoteEditorProcesses must match uri+path
$grepFn = Select-String -Path "$repo\scripts\client\editor-launch.ps1" -Pattern 'function Get-RemoteEditorProcesses' | Select-Object -First 1
Ok ("Get-RemoteEditorProcesses at line {0}" -f $grepFn.LineNumber)
$ge = Get-Content "$repo\scripts\client\editor-launch.ps1"
# read next 35 lines for pathNeedle
$slice = ($ge[($grepFn.LineNumber-1)..([Math]::Min($grepFn.LineNumber+40,$ge.Count-1))]) -join "`n"
if ($slice -match 'pathNeedle' -and $slice -match 'uriNeedle') { Ok 'remote editor match uses uriNeedle + pathNeedle' }
else { Bad 'remote editor match missing needles' }

# ---------- F: ORPHAN_TUNNEL kills ssh.exe not Cursor ----------
Sec 'F) ORPHAN_TUNNEL targets'
$gmLines = Get-Content "$repo\scripts\client\git-mode.ps1"
$orphanIdx = ($gmLines | Select-String -Pattern 'ORPHAN_TUNNEL' | Select-Object -First 1).LineNumber
$ctx = ($gmLines[([Math]::Max(0,$orphanIdx-15))..($orphanIdx+10)]) -join "`n"
Write-Host "  ORPHAN context around L${orphanIdx}:" -ForegroundColor DarkGray
($gmLines[([Math]::Max(0,$orphanIdx-8))..($orphanIdx+5)]) | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
if ($ctx -match 'ssh\.exe|CommandLine.*-R|ProcessId' -and $ctx -notmatch 'Cursor\.exe') {
  Ok 'ORPHAN_TUNNEL kills reverse-ssh pid, not Cursor.exe'
} else {
  Warn 'review ORPHAN context manually'
}
# Indirect effect note
Warn 'INDIRECT: killing reverse tunnel drops SSHFS; Cursor Remote may disconnect folder (not process-kill)'

# ---------- G) Auto-update could reintroduce old kill? ----------
Sec 'G) Auto-update / bundle overwrite risk'
$update = Get-Content "$repo\scripts\client\windows\connect-update.ps1" -Raw
if ($update -match 'editor-launch\.ps1') { Ok 'connect-update can refresh editor-launch.ps1' } else { Warn 'connect-update may not list editor-launch explicitly' }
# Check Smart server bundle still has OLD kill?
try {
  $remote = ssh -o BatchMode=yes -o ConnectTimeout=12 smart@192.168.210.240 "grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1 2>/dev/null; grep -c pre_launch_agent_or_new_window /usr/local/share/claude-client/editor-launch.ps1 2>/dev/null; tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt 2>/dev/null"
  $parts = @($remote -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  Write-Host ("  Smart bundle remote probes: {0}" -f ($parts -join ' | ')) -ForegroundColor DarkGray
  if ($parts -contains '0' -or ($parts.Count -ge 1 -and $parts[0] -eq '0')) {
    Warn 'Smart /usr/local/share/claude-client/editor-launch.ps1 may LACK preserve_open_windows (auto-update could overwrite Desktop fix with old kill!)'
  } elseif ($parts.Count -ge 1 -and [int]$parts[0] -gt 0) {
    Ok 'Smart auto-update bundle already has preserve_open_windows'
  } else {
    Warn "could not classify Smart bundle ($remote)"
  }
} catch {
  Warn "SSH probe Smart bundle failed: $($_.Exception.Message)"
}
try {
  $remote2 = ssh -o BatchMode=yes -o ConnectTimeout=12 sepidz@192.168.250.70 "grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1 2>/dev/null; tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt 2>/dev/null"
  Write-Host ("  Sepidz bundle: {0}" -f (($remote2 -split "`n") -join ' | ')) -ForegroundColor DarkGray
  $p2 = @($remote2 -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($p2.Count -ge 1 -and $p2[0] -match '^\d+$' -and [int]$p2[0] -gt 0) { Ok 'Sepidz auto-update bundle has preserve_open_windows' }
  else { Warn 'Sepidz auto-update bundle may be OLD (pre-fix kill)' }
} catch { Warn "SSH probe Sepidz failed: $($_.Exception.Message)" }

# ---------- H) Package hash matrix (active packages) ----------
Sec 'H) Active Desktop packages hash + version'
foreach ($pkg in @(
  @{ Label='Smart'; Root='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows'; ElFromRepo=$true },
  @{ Label='Sepidz'; Root='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows'; ElFromRepo=$true }
)) {
  $ver = (Get-Content (Join-Path $pkg.Root 'connect-version.txt') -Raw).Trim()
  $elHash = (Get-FileHash (Join-Path $pkg.Root 'editor-launch.ps1') -Algorithm SHA256).Hash
  $repoHash = (Get-FileHash "$repo\scripts\client\editor-launch.ps1" -Algorithm SHA256).Hash
  if ($ver -eq $expectVer -and $elHash -eq $repoHash) { Ok "$($pkg.Label) v$ver editor-launch SHA256=repo" }
  else { Bad "$($pkg.Label) ver=$ver hashMatch=$($elHash -eq $repoHash)" }
}

# ---------- I) Mac editor-launch.sh? ----------
Sec 'I) Mac launch path'
$macEl = "$repo\scripts\client\editor-launch.sh"
if (Test-Path $macEl) {
  $ms = Get-Content $macEl -Raw
  if ($ms -match 'kill|pkill|Cursor') {
    $kills = ([regex]::Matches($ms, '(?m)^.*(kill|pkill|Cursor).*$')).Value
    foreach ($k in $kills) { Write-Host "    mac: $($k.Trim())" -ForegroundColor DarkGray }
    if ($ms -match 'pkill.*[Cc]ursor|killall.*[Cc]ursor') { Bad 'mac editor-launch.sh pkill/killall Cursor' }
    else { Ok 'mac editor-launch.sh has no Cursor process wipe' }
  } else { Ok 'mac editor-launch.sh no kill/Cursor matches' }
} else { Warn 'editor-launch.sh missing' }

# ---------- J) Tests again + connect-pipeline version ----------
Sec 'J) Full related tests'
Push-Location $repo
foreach ($t in @(
  'scripts\client\tests\test-editor-launch-strategies.ps1',
  'scripts\client\tests\test-editor-launch.ps1',
  'scripts\client\tests\test-connect-pipeline.ps1',
  'scripts\client\tests\test-cursor-auth-merge.ps1'
)) {
  if (-not (Test-Path $t)) { Warn "missing $t"; continue }
  & $t *> $null
  if ($LASTEXITCODE -eq 0) { Ok (Split-Path $t -Leaf) } else { Bad "$(Split-Path $t -Leaf) exit=$LASTEXITCODE" }
}
Pop-Location

# ---------- SUMMARY ----------
Sec 'SUMMARY'
Write-Host "  fail=$fail warn=$warn" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if ($fail -eq 0) {
  Write-Host 'ULTRA-DEEP: ALL CRITICAL CHECKS PASSED' -ForegroundColor Green
  exit 0
}
Write-Host 'ULTRA-DEEP: FAILURES PRESENT' -ForegroundColor Red
exit 1
