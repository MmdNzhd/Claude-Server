$ErrorActionPreference='Continue'
$report = New-Object System.Collections.Generic.List[string]
function R([string]$s){ $script:report.Add($s); Write-Host $s }

R '======== 1. SOURCE STRUCTURE ========'
$ui = Get-Content 'scripts\client\connect-ui.ps1' -Raw
$funcs = [regex]::Matches($ui, '(?m)^function ([A-Za-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value }
$dups = $funcs | Group-Object | Where-Object Count -gt 1
R ("funcs={0} dups={1}" -f $funcs.Count, ($(if($dups){($dups|%{"$($_.Name)x$($_.Count)"}) -join ','}else{'none'})))
R ("Sync defs={0} Init defs={1} Write-ConnectLog defs={2}" -f `
  ([regex]::Matches($ui,'(?m)^function Sync-ConnectLogToServer')).Count, `
  ([regex]::Matches($ui,'(?m)^function Initialize-ConnectLog')).Count, `
  ([regex]::Matches($ui,'(?m)^function Write-ConnectLog')).Count)

# Extract Sync body
$s0 = $ui.IndexOf('function Sync-ConnectLogToServer')
$s1 = $ui.IndexOf('function Write-ConnectLog {', $s0)
$sync = $ui.Substring($s0, $s1-$s0)
$w0 = $ui.IndexOf('function Write-ConnectLog {')
$w1 = $ui.IndexOf('function Read-ConnectPrompt', $w0)
$wl = $ui.Substring($w0, $w1-$w0)

R '--- Sync body checks ---'
foreach ($x in @(
  @{n='no return bool'; p={ $sync -notmatch 'return \$false|return \$true|return \$scpOk' }},
  @{n='LastConnectLogSyncOk'; p={ $sync -match 'LastConnectLogSyncOk' }},
  @{n='ControlMaster=no'; p={ $sync -match 'ControlMaster=no' }},
  @{n='watermark write'; p={ $sync -match 'Write-ConnectLogSyncWatermark' }},
  @{n='LOG_SYNC_FAIL once'; p={ $sync -match 'LOG_SYNC_FAIL' -and $sync -match 'ConnectLogSyncFailLogged' }},
  @{n='HOME concat safe'; p={ $sync -match "\`$cat = 'cat" -or $sync -match "\+ \`\$remoteTmp \+" }},
  @{n='nightly find +1'; p={ $sync -match 'mtime \+1' }}
)) { R ("  [{0}] {1}" -f ($(if(& $x.p){'OK'}else{'FAIL'})), $x.n) }

R '--- Write-ConnectLog checks ---'
foreach ($x in @(
  @{n='TRACE/DEBUG early return'; p={ $wl -match "Level -eq 'TRACE'" -and $wl -match "Level -eq 'DEBUG'" }},
  @{n='batch ge 25'; p={ $wl -match '-ge 25' }},
  @{n='WARN/ERROR immediate'; p={ $wl -match "Level -eq 'WARN'" -and $wl -match "Level -eq 'ERROR'" }},
  @{n='Sync call no pipe bool needed'; p={ $wl -match 'Sync-ConnectLogToServer' -and $wl -notmatch 'Sync-ConnectLogToServer \| Out-Null' }}
)) { R ("  [{0}] {1}" -f ($(if(& $x.p){'OK'}else{'WARN'})), $x.n) }

# Callers that might leak False
R '--- Call sites Sync-ConnectLogToServer ---'
Select-String -Path 'scripts\client\*.ps1','scripts\client\windows\*.ps1' -Pattern 'Sync-ConnectLogToServer' |
  ForEach-Object { R ("  {0}:{1}: {2}" -f $_.Path.Replace((Get-Location).Path+'\',''), $_.LineNumber, $_.Line.Trim()) }

R '--- connect.ps1 log path UI ---'
Select-String -Path 'scripts\client\windows\connect.ps1' -Pattern 'ConnectLogPath|same folder as connect' |
  ForEach-Object { R ("  L{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

R '======== 2. MAC PARITY ========'
$sh = Get-Content 'scripts\client\connect-ui.sh' -Raw -ErrorAction SilentlyContinue
if (-not $sh) { R '[FAIL] connect-ui.sh missing' }
else {
  foreach ($x in @(
    @{n='sync function'; p={ $sh -match 'sync_connect_log|SyncConnectLog|connect_log_sync' }},
    @{n='local log dir'; p={ $sh -match 'claude-connect/logs|\.config/claude-connect' }},
    @{n='watermark'; p={ $sh -match 'sync-offset|SYNC_OFFSET|watermark' }},
    @{n='BOOTSTRAP or session'; p={ $sh -match 'BOOTSTRAP|session start|WriteConnectLog|write_connect_log' }}
  )) { R ("  [{0}] {1}" -f ($(if(& $x.p){'OK'}else{'FAIL'})), $x.n) }
  # show sync-related function names
  [regex]::Matches($sh, '(?m)^[a-z_][a-z0-9_]*\(\)') | ForEach-Object { $_.Value } |
    Where-Object { $_ -match 'log|sync' } | ForEach-Object { R ("  fn $_") }
}

R '======== 3. DEPLOYED BUNDLE vs SOURCE ========'
$srcHash = (Get-FileHash 'scripts\client\connect-ui.ps1' -Algorithm SHA256).Hash
$verSrc = (Get-Content 'scripts\client\windows\connect-version.txt' -Raw).Trim()
R ("source connect-ui sha256={0} version.txt={1}" -f $srcHash.Substring(0,16), $verSrc)

$remote = ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 @'
set -e
VER=$(cat /usr/local/share/claude-client/connect-version.txt)
SHA=$(sha256sum /usr/local/share/claude-client/connect-ui.ps1 | awk "{print \$1}")
echo "ver=$VER"
echo "sha=$SHA"
# critical markers
python3 - <<'PY'
from pathlib import Path
t=Path('/usr/local/share/claude-client/connect-ui.ps1').read_text(errors='replace')
print('dup_sync', t.count('function Sync-ConnectLogToServer'))
print('dup_init', t.count('function Initialize-ConnectLog'))
s=t.find('function Sync-ConnectLogToServer'); e=t.find('function Write-ConnectLog', s); b=t[s:e]
print('bool_returns', [x for x in ('return $false','return $true','return $scpOk') if x in b] or 'NONE')
print('LastOk', 'LastConnectLogSyncOk' in b)
print('home_safe', ("$cat = 'cat" in b) or ("+ $remoteTmp +" in b))
print('fail_log', 'LOG_SYNC_FAIL' in b)
w=t[t.find('function Write-ConnectLog'):t.find('function Read-ConnectPrompt')]
print('skip_trace', "Level -eq 'TRACE'" in w)
print('batch25', '-ge 25' in w)
cp=Path('/usr/local/share/claude-client/connect.ps1').read_text(errors='replace')
print('bad_log_msg', 'same folder as connect.bat' in cp)
print('good_log_msg', 'ConnectLogPath' in cp and 'Log:' in cp)
PY
# cleanup script present?
ls -la /usr/local/share/claude-client/claude-connect-logs-cleanup.sh 2>/dev/null || ls /etc/cron* 2>/dev/null | head -3 || true
grep -l connect-logs-cleanup /etc/cron.d/* /etc/cron.daily/* 2>/dev/null || echo 'no_cron_hit'
'@
R $remote

$smartV = ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt'
R ("Smart frozen version={0}" -f $smartV.Trim())

R '======== 4. LOCAL vs SERVER LOG DEEP DIFF ========'
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
# copy despite lock
$dst = Join-Path $env:TEMP 'deep-local.log'
$fs = [System.IO.File]::Open($local, 'Open', 'Read', 'ReadWrite')
try { $o=[System.IO.File]::Create($dst); try{$fs.CopyTo($o)} finally{$o.Close()} } finally { $fs.Close() }
$li = Get-Item $dst
R ("local_copy bytes={0}" -f $li.Length)

# key markers with counts + first ts
$markers = @(
  'BOOTSTRAP: connect.bat start',
  'UPDATE:',
  '======== session start',
  'DECISION: project_select',
  'STEP end: Server setup',
  'STEP end: Loading projects',
  'SESSION_LOOP begin',
  'STEP end: SSH tunnel',
  'STEP end: Mounting files',
  'STEP end: Syncing Cursor auth',
  'LAUNCH begin',
  'Connection dropped',
  'recover',
  'LOG_SYNC_FAIL',
  'EXIT_WAIT',
  'False'
)
R '--- local markers ---'
foreach ($m in $markers) {
  $hits = @(Select-String -Path $dst -SimpleMatch $m)
  $first = if ($hits.Count) { ($hits[0].Line.Substring(0,[Math]::Min(100,$hits[0].Line.Length))) } else { '-' }
  R ("  n={0,5} {1} | {2}" -f $hits.Count, $m, $first)
}

# pull server copy via scp
$srvLocal = Join-Path $env:TEMP 'deep-server.log'
scp -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srvLocal
R ("server_copy bytes={0}" -f (Get-Item $srvLocal).Length)

R '--- server markers ---'
foreach ($m in $markers) {
  $hits = @(Select-String -Path $srvLocal -SimpleMatch $m)
  $first = if ($hits.Count) { ($hits[0].Line.Substring(0,[Math]::Min(100,$hits[0].Line.Length))) } else { '-' }
  R ("  n={0,5} {1} | {2}" -f $hits.Count, $m, $first)
}

# session ids
R '--- sessions ---'
$locSess = Select-String -Path $dst -Pattern 'session start v([0-9.]+) .* session=([a-f0-9]+)' | ForEach-Object { $_.Matches[0].Groups[2].Value + ' v' + $_.Matches[0].Groups[1].Value }
$srvSess = Select-String -Path $srvLocal -Pattern 'session start v([0-9.]+) .* session=([a-f0-9]+)' | ForEach-Object { $_.Matches[0].Groups[2].Value + ' v' + $_.Matches[0].Groups[1].Value }
R ("local sessions: {0}" -f (($locSess | Select-Object -Unique) -join ', '))
R ("server sessions: {0}" -f (($srvSess | Select-Object -Unique) -join ', '))

# timeline of STEP end
R '--- local STEP timing (first session) ---'
Select-String -Path $dst -Pattern 'STEP end:' | Select-Object -First 25 | ForEach-Object {
  R ("  {0}" -f $_.Line.Substring(0,[Math]::Min(140,$_.Line.Length)))
}

# level histogram
R '--- level histogram local ---'
Select-String -Path $dst -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
  Group-Object | Sort-Object Count -Descending | ForEach-Object { R ("  {0}={1}" -f $_.Name, $_.Count) }

R '--- level histogram server ---'
Select-String -Path $srvLocal -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
  Group-Object | Sort-Object Count -Descending | ForEach-Object { R ("  {0}={1}" -f $_.Name, $_.Count) }

# first/last timestamps
$locLines = Get-Content $dst
$srvLines = Get-Content $srvLocal
R ("local first: {0}" -f $locLines[0].Substring(0,[Math]::Min(120,$locLines[0].Length)))
R ("local last:  {0}" -f $locLines[-1].Substring(0,[Math]::Min(120,$locLines[-1].Length)))
R ("server first:{0}" -f $srvLines[0].Substring(0,[Math]::Min(120,$srvLines[0].Length)))
R ("server last: {0}" -f $srvLines[-1].Substring(0,[Math]::Min(120,$srvLines[-1].Length)))

# overlap: is server a prefix of local (ignoring BOM)?
$locBytes = [System.IO.File]::ReadAllBytes($dst)
$srvBytes = [System.IO.File]::ReadAllBytes($srvLocal)
# strip UTF8 BOM if present
function Strip-Bom([byte[]]$b) {
  if ($b.Length -ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF) {
    $n = New-Object byte[] ($b.Length-3); [Array]::Copy($b,3,$n,0,$n.Length); return $n
  }
  return $b
}
$lb = Strip-Bom $locBytes; $sb = Strip-Bom $srvBytes
$prefix = $true
$cmpLen = [Math]::Min($lb.Length, $sb.Length)
# compare first 64KB and check if server content appears in local
$sample = [Math]::Min(65536, $sb.Length)
$matchStart = $true
for ($i=0; $i -lt $sample; $i++) { if ($lb[$i] -ne $sb[$i]) { $matchStart=$false; break } }
R ("server_is_local_prefix_64k={0} local_len={1} server_len={2} gap={3}" -f $matchStart, $lb.Length, $sb.Length, ($lb.Length-$sb.Length))

# find first differing offset if not prefix
if (-not $matchStart) {
  $max = [Math]::Min($lb.Length, $sb.Length, 2000000)
  $diffAt = -1
  for ($i=0; $i -lt $max; $i++) { if ($lb[$i] -ne $sb[$i]) { $diffAt=$i; break } }
  R ("first_diff_offset={0}" -f $diffAt)
  if ($diffAt -ge 0) {
    $ls = [Text.Encoding]::UTF8.GetString($lb, [Math]::Max(0,$diffAt-40), [Math]::Min(120, $lb.Length-[Math]::Max(0,$diffAt-40)))
    $ss = [Text.Encoding]::UTF8.GetString($sb, [Math]::Max(0,$diffAt-40), [Math]::Min(120, $sb.Length-[Math]::Max(0,$diffAt-40)))
    R ("local@diff: {0}" -f ($ls -replace "`r|`n",' '))
    R ("server@diff: {0}" -f ($ss -replace "`r|`n",' '))
  }
}

R '======== 5. LIVE SYNC STRESS (isolated file) ========'
$tdir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$tfile = Join-Path $tdir 'deep-sync-stress.log'
Remove-Item $tfile -Force -EA SilentlyContinue
Remove-Item ($tfile+'.sync-offset') -Force -EA SilentlyContinue
. .\scripts\client\connect-ui.ps1
$script:Alias = 'smart@192.168.250.70'
$script:ConnectLogPath = $tfile
$script:ConnectSessionId = 'deepstress'
$script:ConnectLogSyncOffset = 0
$script:ConnectLogSyncFailLogged = $false
$script:ConnectLogWriter = [IO.StreamWriter]::new($tfile, $true, [Text.UTF8Encoding]::new($false))
$script:ConnectLogWriter.AutoFlush = $true

# 30 INFO lines -> should sync at 25
$tag = "DEEPSTRESS_{0}" -f (Get-Date -Format 'HHmmss')
1..30 | ForEach-Object { Write-ConnectLog ("$tag line=$_") 'INFO' }
# TRACE should not bump sync counter path (early return) - already synced
Write-ConnectLog "$tag TRACE_ONLY" 'TRACE'
Write-ConnectLog "$tag WARN_FLUSH" 'WARN'
$script:ConnectLogWriter.Close(); $script:ConnectLogWriter=$null

$pipeLeak = $false
# already synced via Write-ConnectLog; check server
$found = ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log; grep -c TRACE_ONLY ~/.claude/logs/connect-20260719.log; grep $tag ~/.claude/logs/connect-20260719.log | tail -3"
R ("stress server grep: {0}" -f ($found -replace "`n",' | '))
R ("LastConnectLogSyncOk={0} offset={1}" -f $script:LastConnectLogSyncOk, $script:ConnectLogSyncOffset)

# False leak test: capture output of 5 syncs
$leaks = New-Object System.Collections.Generic.List[string]
1..5 | ForEach-Object {
  $script:ConnectLogSyncOffset = 0  # resync whole small file
  $o = Sync-ConnectLogToServer | Out-String
  if (-not [string]::IsNullOrWhiteSpace($o)) { $leaks.Add($o.Trim()) }
}
R ("pipeline_leaks={0} values=[{1}]" -f $leaks.Count, ($leaks -join ','))

Remove-Item $tfile -Force -EA SilentlyContinue
Remove-Item ($tfile+'.sync-offset') -Force -EA SilentlyContinue

R '======== 6. PERF / SLOWNESS ROOT CAUSES FROM LOG ========'
# aggregate PERF[cim_query] count and max
$cim = @(Select-String -Path $dst -Pattern 'PERF\[cim_query\] ms=(\d+)')
$cimMs = $cim | ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
R ("cim_query events={0} max_ms={1} sum_ms={2}" -f $cim.Count, (($cimMs|Measure-Object -Max).Maximum), (($cimMs|Measure-Object -Sum).Sum))
$stale = @(Select-String -Path $dst -Pattern 'STALE_FORWARD|ORPHAN_TUNNEL|port still busy')
R ("stale/orphan events={0}" -f $stale.Count)
$stale | Select-Object -First 8 | ForEach-Object { R ("  {0}" -f $_.Line.Substring(0,[Math]::Min(130,$_.Line.Length))) }

# estimate sync attempts if every line synced (old bug)
$infoN = ([regex]::Matches((Get-Content $dst -Raw), '\[INFO\]')).Count
R ("If sync-every-line on ALL levels: would attempt ~{0} scp calls (old .9 bug)" -f $locLines.Count)
R ("With .11 policy: TRACE/DEBUG local-only; INFO sync ~every 25 => ~{0} syncs for INFO-only" -f [Math]::Ceiling($infoN/25.0))

R '======== 7. WATERMARK / CONF ========'
$wm = $local + '.sync-offset'
if (Test-Path $wm) { R ("watermark={0} local_size={1}" -f (Get-Content $wm -Raw).Trim(), (Get-Item $local).Length) }
else { R 'watermark: MISSING (active .9 session never advanced watermark successfully)' }
$cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
if (Test-Path $cfg) {
  Get-Content $cfg | Where-Object { $_ -match 'SERVER_IP|REMOTE_USER|GIT_MODE|ALIAS|EDITOR' } | ForEach-Object { R ("  conf: $_") }
}

R '======== DONE ========'
$out = Join-Path $env:TEMP 'deep-audit-report.txt'
$report | Set-Content $out -Encoding utf8
R ("report written: $out")
Remove-Item $dst,$srvLocal -Force -EA SilentlyContinue
