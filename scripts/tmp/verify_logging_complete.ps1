$ErrorActionPreference = 'Continue'
$fail = 0
function Ok($m) { Write-Host "[OK] $m" }
function Bad($m) { Write-Host "[FAIL] $m"; $script:fail++ }
function Info($m) { Write-Host "[..] $m" }

# --- 1) Source file integrity ---
$ui = 'scripts\client\connect-ui.ps1'
$c = Get-Content $ui -Raw
$funcs = [regex]::Matches($c, '(?m)^function ([A-Za-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value }
$dup = $funcs | Group-Object | Where-Object { $_.Count -gt 1 }
if ($dup) { Bad ("duplicate functions: " + (($dup | ForEach-Object { $_.Name + 'x' + $_.Count }) -join ', ')) }
else { Ok 'no duplicate functions in connect-ui.ps1' }

$syncCount = ([regex]::Matches($c, '(?m)^function Sync-ConnectLogToServer')).Count
if ($syncCount -eq 1) { Ok 'exactly one Sync-ConnectLogToServer' } else { Bad "Sync count=$syncCount" }

$syncStart = $c.IndexOf('function Sync-ConnectLogToServer')
$syncEnd = $c.IndexOf('function Write-ConnectLog {', $syncStart)
$syncBody = $c.Substring($syncStart, $syncEnd - $syncStart)
foreach ($bad in @('return $false','return $true','return $scpOk')) {
  if ($syncBody.Contains($bad)) { Bad "Sync still returns: $bad" }
}
if ($syncBody.Contains('LastConnectLogSyncOk')) { Ok 'Sync uses LastConnectLogSyncOk (no pipeline bool)' } else { Bad 'missing LastConnectLogSyncOk' }
if ($syncBody.Contains("+ `$remoteTmp +") -or $syncBody.Contains("+ $remoteTmp +") -or ($syncBody -match "\+ \$remoteTmp \+")) {
  Ok 'remote $cat builds path without expanding Windows $HOME'
} elseif ($syncBody -match "cat .*\$HOME/") {
  # check it's single-quoted concatenation
  if ($syncBody -match "\`$cat = 'cat") { Ok 'cat uses single-quoted remote HOME' }
  else { Bad 'cat may still expand Windows $HOME' }
} else { Bad 'could not verify cat $HOME fix' }

$wl = $c.Substring($c.IndexOf('function Write-ConnectLog {'), 900)
if ($wl -match "TRACE.*DEBUG|Level -eq 'TRACE'") { Ok 'Write-ConnectLog skips TRACE/DEBUG sync' } else { Bad 'TRACE/DEBUG sync skip missing' }
if ($wl -match 'ConnectLogLinesSinceSync -ge 25') { Ok 'INFO sync batched every 25 lines' } else { Bad 'batch 25 missing' }

# parse
try { . .\$ui; Ok 'connect-ui.ps1 parses' } catch { Bad ("parse: " + $_.Exception.Message) }

# connect.ps1 log path message
$cp = Get-Content 'scripts\client\windows\connect.ps1' -Raw
if ($cp -match 'Log: \$\(\$script:ConnectLogPath\)') { Ok 'session box shows full local log path' }
elseif ($cp -match 'same folder as connect\.bat') { Bad 'still says same folder as connect.bat' }
else { Info 'log path message pattern not found (check manually)' }

# --- 2) Deployed Sepidz bundle version ---
$verRemote = (ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
$verSmart  = (ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
if ($verRemote -eq '20260719.11') { Ok "Sepidz bundle=$verRemote" } else { Bad "Sepidz bundle=$verRemote expected 20260719.11" }
if ($verSmart -eq '20260717.22') { Ok "Smart frozen=$verSmart" } else { Bad "Smart=$verSmart (should stay 20260717.22)" }

# Deployed connect-ui on server has the fixes?
$remoteUiCheck = ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 @'
grep -c 'LastConnectLogSyncOk' /usr/local/share/claude-client/connect-ui.ps1
grep -c "Level -eq 'TRACE'" /usr/local/share/claude-client/connect-ui.ps1
grep -c 'same folder as connect.bat' /usr/local/share/claude-client/connect.ps1 || true
grep -c 'ConnectLogPath' /usr/local/share/claude-client/connect.ps1 | head -1
# bool return should be gone from Sync
python3 - <<'PY'
from pathlib import Path
t=Path('/usr/local/share/claude-client/connect-ui.ps1').read_text(errors='replace')
s=t.find('function Sync-ConnectLogToServer')
e=t.find('function Write-ConnectLog', s)
body=t[s:e]
bad=[x for x in ('return $false','return $true','return $scpOk') if x in body]
print('sync_bools', bad if bad else 'NONE')
print('dup_sync', t.count('function Sync-ConnectLogToServer'))
print('home_concat', ('+ $remoteTmp +' in body) or ("+ `$remoteTmp +" in body) or ("'+ $remoteTmp +'" in body) or ("' + $remoteTmp + '" in body))
# show cat line
for line in body.splitlines():
    if 'remoteTmp' in line and 'cat' in line:
        print('CAT', line.strip()[:160])
PY
'@
Info "remote ui check:`n$remoteUiCheck"

# --- 3) Local log completeness ---
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
if (-not (Test-Path $local)) { Bad "local log missing: $local" }
else {
  $li = Get-Item $local
  $lines = Get-Content $local
  Ok ("local log exists bytes=$($li.Length) lines=$($lines.Count)")
  $hasBoot = ($lines | Select-String -SimpleMatch 'BOOTSTRAP: connect.bat start' | Select-Object -First 1)
  $hasSess = ($lines | Select-String -SimpleMatch 'session start v20260719' | Select-Object -First 1)
  $hasDec  = ($lines | Select-String -SimpleMatch 'DECISION: project_select' | Select-Object -First 1)
  $hasReady= ($lines | Select-String -Pattern 'server_ready|SESSION_LOOP begin|Opening Cursor|LAUNCH begin' | Select-Object -First 1)
  if ($hasBoot) { Ok 'has BOOTSTRAP' } else { Bad 'missing BOOTSTRAP' }
  if ($hasSess) { Ok 'has session start' } else { Bad 'missing session start' }
  if ($hasDec)  { Ok 'has DECISION project_select' } else { Bad 'missing DECISION' }
  if ($hasReady){ Ok 'has ready/launch phase' } else { Bad 'missing ready phase' }
  $first = $lines[0]
  $last = $lines[-1]
  Info "first: $($first.Substring(0,[Math]::Min(120,$first.Length)))"
  Info "last:  $($last.Substring(0,[Math]::Min(120,$last.Length)))"
}

# --- 4) Server log present + overlap with local ---
$srvStat = ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 'wc -c $HOME/.claude/logs/connect-20260719.log; head -n 1 $HOME/.claude/logs/connect-20260719.log; grep -c BOOTSTRAP $HOME/.claude/logs/connect-20260719.log; grep -c "session start" $HOME/.claude/logs/connect-20260719.log; grep -c "DECISION: project_select" $HOME/.claude/logs/connect-20260719.log'
Info "server log:`n$srvStat"
if ($srvStat -match 'BOOTSTRAP' -or ($srvStat -split "`n") -match '^[0-9]+$') {
  $parts = $srvStat -split "`n"
  Ok 'server log file readable'
}

# --- 5) Live sync smoke test (small append) ---
$probe = "VERIFY_PROBE $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') pid=$PID"
# Use Sync function if we can init minimally
$script:Alias = 'smart@192.168.250.70'
$script:ConnectLogPath = $local
$script:ConnectLogSyncOffset = 0
$script:ConnectLogWriter = $null
$script:ConnectSessionId = 'verifyprobe'
# append probe then sync
Add-Content -LiteralPath $local -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [INFO] [verifyprobe] $probe" -Encoding UTF8
# watermark at end- of file before probe? Better: sync from watermark file or 0 may re-upload huge - use current watermark
$wmPath = $local + '.sync-offset'
$beforeSize = (Get-Item $local).Length
if (Test-Path $wmPath) {
  $wm = [int]((Get-Content $wmPath -Raw).Trim())
  Info "watermark before sync=$wm file=$beforeSize"
  $script:ConnectLogSyncOffset = $wm
} else {
  # only ship last 2KB to avoid huge reupload
  $script:ConnectLogSyncOffset = [Math]::Max(0, $beforeSize - 2048)
  Info "no watermark; syncing tail from $($script:ConnectLogSyncOffset)"
}

# Capture any pipeline output from Sync (should be empty)
$out = @(Sync-ConnectLogToServer 6>&1 | Out-String)
$pipe = ($out | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($pipe)) { Ok 'Sync emits nothing to pipeline (no False)' }
else { Bad "Sync pipeline leaked: $pipe" }
Info "LastConnectLogSyncOk=$script:LastConnectLogSyncOk"

$found = ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 "grep -F '$probe' `$HOME/.claude/logs/connect-20260719.log | tail -1"
if ($found -and $found -match 'VERIFY_PROBE') { Ok "live sync landed on server: $found" }
else { Bad "live sync probe NOT on server. found='$found'" }

Write-Host ''
if ($fail -eq 0) { Write-Host '==== ALL CHECKS PASSED ====' } else { Write-Host "==== FAILED: $fail ===="; exit 1 }
