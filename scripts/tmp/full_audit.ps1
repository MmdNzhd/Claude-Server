$ErrorActionPreference = 'Continue'
$script:fail = 0
function Ok([string]$m){ Write-Host ("OK  " + $m) -ForegroundColor Green }
function Bad([string]$m){ Write-Host ("BAD " + $m) -ForegroundColor Red; $script:fail++ }
function Info([string]$m){ Write-Host ("    " + $m) -ForegroundColor DarkGray }

Write-Host ''
Write-Host '========== 1) VERSIONS ==========' -ForegroundColor Cyan
$srcVer = (Get-Content 'scripts\client\windows\connect-version.txt' -Raw).Trim()
$psVerLine = (Select-String -Path 'scripts\client\windows\connect.ps1' -Pattern "ConnectVersion\s*=\s*'([^']+)'" | Select-Object -First 1).Matches.Groups[1].Value
Ok ("source version.txt=" + $srcVer)
if ($psVerLine -eq $srcVer) { Ok ("connect.ps1 ConnectVersion=" + $psVerLine) } else { Bad ("connect.ps1=" + $psVerLine + " != version.txt=" + $srcVer) }

function Get-RemoteVer([string]$Target) {
  $out = Join-Path $env:TEMP ('ver-' + ($Target -replace '[^a-z0-9]','') + '.txt')
  $p = Start-Process -FilePath ssh -ArgumentList @(
    '-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',
    $Target, "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
  ) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
  if (-not $p.WaitForExit(15000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $out -Raw -EA SilentlyContinue)+'').Trim()
}
$sep = Get-RemoteVer 'sepidz@192.168.250.70'
$sma = Get-RemoteVer 'smart@192.168.210.240'
if ($sep -eq '20260719.15') { Ok ('Sepidz server=' + $sep) } else { Bad ('Sepidz server=' + $sep + ' (want 20260719.15)') }
if ($sma -eq '20260717.22') { Ok ('Smart frozen=' + $sma) } else { Bad ('Smart=' + $sma + ' (want 20260717.22 FROZEN)') }

$pkgRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code'
$pkgWin = Join-Path $pkgRoot 'windows'
$pkgMac = Join-Path $pkgRoot 'mac'
if (-not (Test-Path $pkgWin)) { Bad ('package missing: ' + $pkgWin) }
else {
  $pkgVer = (Get-Content (Join-Path $pkgWin 'connect-version.txt') -Raw).Trim()
  if ($pkgVer -eq '20260719.15') { Ok ('package windows ver=' + $pkgVer) } else { Bad ('package ver=' + $pkgVer) }
  $macVer = (Get-Content (Join-Path $pkgMac 'connect-version.txt') -Raw).Trim()
  if ($macVer -eq $pkgVer) { Ok ('package mac ver=' + $macVer) } else { Bad ('mac ver=' + $macVer + ' != win=' + $pkgVer) }
}

Write-Host ''
Write-Host '========== 2) WINDOWS FIX MARKERS (SOURCE) ==========' -ForegroundColor Cyan
$srcChecks = @(
  @{f='scripts\client\connect-ui.ps1'; p="CLAUDE_CONNECT_PERF_LOG -eq '1'"; n='PERF default OFF'},
  @{f='scripts\client\connect-ui.ps1'; p='Enter-ConnectSingleInstance'; n='single-instance mutex'},
  @{f='scripts\client\connect-ui.ps1'; p='Exit-ConnectSingleInstance'; n='mutex release'},
  @{f='scripts\client\connect-ui.ps1'; p='FileShare.ReadWrite'; n='log FileShare.ReadWrite'},
  @{f='scripts\client\connect-ui.ps1'; p='Ensure-ConnectLogWriter'; n='reopen writer'},
  @{f='scripts\client\connect-ui.ps1'; p='Get-ConnectLogDayPath'; n='day path / midnight'},
  @{f='scripts\client\connect-ui.ps1'; p='LastConnectLogSyncOk'; n='no False spam'},
  @{f='scripts\client\connect-ui.ps1'; p='512KB'; n='sync chunk 512KB'},
  @{f='scripts\client\connect-ui.ps1'; p='.sync-offset'; n='sync watermark'},
  @{f='scripts\client\connect-ui.ps1'; p='claude-connect\logs'; n='durable local logs dir'},
  @{f='scripts\client\git-mode.ps1'; p='LastTunnelSyncTraceAt'; n='TUNNEL_SYNC 30s throttle'},
  @{f='scripts\client\git-mode.ps1'; p='$i -le 4'; n='STALE wait shortened'},
  @{f='scripts\client\git-mode.ps1'; p='Milliseconds 250'; n='STALE sleep 250ms'},
  @{f='scripts\client\windows\connect.ps1'; p='Enter-ConnectSingleInstance'; n='mutex wired in connect.ps1'},
  @{f='scripts\client\windows\connect.ps1'; p='lastEditorCheckAt'; n='editor CIM every 2s'},
  @{f='scripts\client\windows\connect.ps1'; p='Start-Sleep -Milliseconds 500'; n='session loop 500ms'},
  @{f='scripts\client\windows\connect.ps1'; p='Sync-ConnectLogToServer | Out-Null'; n='sync Out-Null'},
  @{f='scripts\client\windows\connect.bat'; p='BOOTSTRAP'; n='bat BOOTSTRAP line'},
  @{f='scripts\client\windows\connect.bat'; p='NewGuid'; n='bat session guid'}
)
foreach ($c in $srcChecks) {
  if (Select-String -Path $c.f -Pattern $c.p -SimpleMatch -Quiet) { Ok $c.n }
  else { Bad ($c.n + ' missing in ' + $c.f) }
}

Write-Host ''
Write-Host '========== 3) PACKAGE == SOURCE (SHA) ==========' -ForegroundColor Cyan
$pairs = @(
  @('scripts\client\connect-ui.ps1', 'windows\connect-ui.ps1'),
  @('scripts\client\git-mode.ps1', 'windows\git-mode.ps1'),
  @('scripts\client\windows\connect.bat', 'windows\connect.bat'),
  @('scripts\client\windows\connect-update.ps1', 'windows\connect-update.ps1'),
  @('scripts\client\connect-ui.sh', 'mac\connect-ui.sh'),
  @('scripts\client\git-mode.sh', 'mac\git-mode.sh')
)
foreach ($pr in $pairs) {
  $a = (Get-FileHash $pr[0] -Algorithm SHA256).Hash
  $b = (Get-FileHash (Join-Path $pkgRoot $pr[1]) -Algorithm SHA256).Hash
  if ($a -eq $b) { Ok ('SHA match ' + $pr[1]) }
  else { Bad ('SHA DIFF ' + $pr[1] + ' src=' + $a.Substring(0,12) + ' pkg=' + $b.Substring(0,12)) }
}
$cp = Get-Content (Join-Path $pkgWin 'connect.ps1') -Raw
if ($cp -match 'claude-server-sepidz') { Ok 'package alias=claude-server-sepidz' } else { Bad 'package alias missing' }
if ($cp -match '192\.168\.250\.70') { Ok 'package IP=250.70' } else { Bad 'package IP missing' }
if ($cp -notmatch '192\.168\.210\.240') { Ok 'package has no Smart IP' } else { Bad 'package still has Smart IP' }
if ($cp -match "ConnectVersion = '20260719.15'") { Ok 'package ConnectVersion=.15' } else { Bad 'package ConnectVersion wrong' }

Write-Host ''
Write-Host '========== 4) REMOTE BUNDLE SPOT-CHECK ==========' -ForegroundColor Cyan
$cmd = @'
echo MUTEX=$(grep -c Enter-ConnectSingleInstance /usr/local/share/claude-client/connect-ui.ps1)
echo PERF=$(grep -c CLAUDE_CONNECT_PERF_LOG /usr/local/share/claude-client/connect-ui.ps1)
echo TUNNEL=$(grep -c LastTunnelSyncTraceAt /usr/local/share/claude-client/git-mode.ps1)
echo EDITOR=$(grep -c lastEditorCheckAt /usr/local/share/claude-client/connect.ps1)
echo BOOT=$(grep -c BOOTSTRAP /usr/local/share/claude-client/connect.bat)
echo ALIAS=$(grep -c claude-server-sepidz /usr/local/share/claude-client/connect.ps1)
echo IP=$(grep -c 192.168.250.70 /usr/local/share/claude-client/connect.ps1)
echo VER=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
echo SMARTIP=$(grep -c 192.168.210.240 /usr/local/share/claude-client/connect.ps1 || true)
'@
$outF = Join-Path $env:TEMP 'remote-spot.txt'
$p = Start-Process ssh -ArgumentList @(
  '-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no',
  'sepidz@192.168.250.70', $cmd
) -NoNewWindow -PassThru -RedirectStandardOutput $outF -RedirectStandardError ($outF + '.err')
if (-not $p.WaitForExit(25000)) { try{$p.Kill()}catch{}; Bad 'remote spot-check TIMEOUT' }
else {
  $txt = (Get-Content $outF -Raw)
  foreach ($line in (($txt+'') -split "`n")) {
    $line = $line.Trim()
    if (-not $line) { continue }
    Info $line
    if ($line -match '^MUTEX=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote mutex' } else { Bad 'remote mutex=0' } }
    elseif ($line -match '^PERF=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote PERF flag' } else { Bad 'remote PERF=0' } }
    elseif ($line -match '^TUNNEL=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote tunnel throttle' } else { Bad 'remote tunnel=0' } }
    elseif ($line -match '^EDITOR=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote editor throttle' } else { Bad 'remote editor=0' } }
    elseif ($line -match '^BOOT=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote BOOTSTRAP' } else { Bad 'remote BOOT=0' } }
    elseif ($line -match '^ALIAS=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote alias' } else { Bad 'remote alias=0' } }
    elseif ($line -match '^IP=(\d+)$') { if ([int]$Matches[1] -ge 1) { Ok 'remote sepidz IP' } else { Bad 'remote IP=0' } }
    elseif ($line -match '^VER=(.+)$') { if ($Matches[1] -eq '20260719.15') { Ok ('remote VER=' + $Matches[1]) } else { Bad ('remote VER=' + $Matches[1]) } }
    elseif ($line -match '^SMARTIP=(\d+)$') { if ([int]$Matches[1] -eq 0) { Ok 'remote no Smart IP' } else { Bad ('remote still has Smart IP count=' + $Matches[1]) } }
  }
}

Write-Host ''
Write-Host '========== 5) MAC / SH PARITY ==========' -ForegroundColor Cyan
$macChecks = @(
  @{f='scripts\client\connect-ui.sh'; p='flock'; n='Mac single-instance flock'},
  @{f='scripts\client\connect-ui.sh'; p='sync_connect_log_to_server'; n='Mac sync'},
  @{f='scripts\client\connect-ui.sh'; p='.sync-offset'; n='Mac watermark'},
  @{f='scripts\client\connect-ui.sh'; p='TRACE'; n='Mac TRACE local-only path'},
  @{f='scripts\client\connect-ui.sh'; p='day_path'; n='Mac midnight rollover'},
  @{f='scripts\client\git-mode.sh'; p='_LAST_TUNNEL_TRACE'; n='Mac TUNNEL 30s throttle'},
  @{f='scripts\client\git-mode.sh'; p='seq 1 4'; n='Mac STALE seq 1..4'},
  @{f='scripts\client\mac\connect.sh'; p='enter_connect_single_instance'; n='Mac mutex call'},
  @{f='scripts\client\mac\connect.sh'; p='init_connect_log'; n='Mac init log'},
  @{f='scripts\client\mac\connect.sh'; p='flush_connect_log_to_server'; n='Mac flush on exit'}
)
foreach ($c in $macChecks) {
  if (Select-String -Path $c.f -Pattern $c.p -SimpleMatch -Quiet) { Ok $c.n }
  else { Bad ($c.n + ' missing') }
}

Write-Host ''
Write-Host '========== 6) PARSE + FUNCS ==========' -ForegroundColor Cyan
try {
  . .\scripts\client\connect-ui.ps1
  . .\scripts\client\git-mode.ps1
  Ok 'PowerShell parse connect-ui + git-mode'
} catch {
  Bad ('parse fail: ' + $_.Exception.Message)
}
if (Get-Command Sync-ConnectLogToServer -EA SilentlyContinue) { Ok 'Sync-ConnectLogToServer present' } else { Bad 'Sync missing' }
if (Get-Command Enter-ConnectSingleInstance -EA SilentlyContinue) { Ok 'Enter-ConnectSingleInstance present' } else { Bad 'Enter missing' }
if (Get-Command Ensure-ConnectLogWriter -EA SilentlyContinue) { Ok 'Ensure-ConnectLogWriter present' } else { Bad 'Ensure writer missing' }

Write-Host ''
Write-Host '========== 7) ACTIVE CONNECT / FOLDERS ==========' -ForegroundColor Cyan
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='cmd.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'connect\.(ps1|bat)') })
if ($procs.Count -eq 0) { Ok 'no connect process running (good for clean restart)' }
else {
  foreach ($pr in $procs) {
    $cl = $pr.CommandLine
    if ($cl.Length -gt 200) { $cl = $cl.Substring(0,200) }
    Info ('PID=' + $pr.ProcessId + ' ' + $cl)
    if ($cl -match 'Claude-Connect\\' -or $cl -match 'claude-code-client') {
      Bad 'running from Smart/old client folder - close it'
    } else {
      Ok ('running connect PID=' + $pr.ProcessId)
    }
  }
}

$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-version.txt'
if (Test-Path $desk) {
  $dv = (Get-Content $desk -Raw).Trim()
  Info ('Desktop\Claude-Connect ver=' + $dv + ' (Smart leftover - DO NOT use for Sepidz)')
  if ($dv -ne '20260719.15') { Ok 'confirmed Desktop Claude-Connect is NOT Sepidz .15' }
}

$candidates = @(
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows')
)
foreach ($c in $candidates) {
  $vf = Join-Path $c 'connect-version.txt'
  if (Test-Path $vf) {
    $v = (Get-Content $vf -Raw).Trim()
    Info ('folder ' + $c + ' => ' + $v)
  }
}

Write-Host ''
Write-Host '========== 8) LOCAL LOG STATE ==========' -ForegroundColor Cyan
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
if (Test-Path $logDir) {
  Ok ('log dir exists: ' + $logDir)
  Get-ChildItem $logDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object {
    Info ($_.Name + '  ' + $_.Length + ' bytes  ' + $_.LastWriteTime.ToString('HH:mm:ss'))
  }
  $today = Join-Path $logDir ('connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
  if (Test-Path $today) {
    Info '--- last 12 local lines ---'
    Get-Content $today -Tail 12 -EA SilentlyContinue | ForEach-Object { Info $_ }
  }
} else {
  Info 'log dir not created yet (will appear on first connect.bat)'
}

Write-Host ''
Write-Host '========== 9) SERVER LOG TAIL ==========' -ForegroundColor Cyan
$slog = Join-Path $env:TEMP 'server-log-tail.txt'
$p2 = Start-Process ssh -ArgumentList @(
  '-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no',
  'sepidz@192.168.250.70',
  "ls -la ~/.claude/logs/connect-*.log 2>/dev/null | tail -5; echo ====; tail -n 8 ~/.claude/logs/connect-\$(date +%Y%m%d).log 2>/dev/null || echo NO_TODAY_SERVER_LOG"
) -NoNewWindow -PassThru -RedirectStandardOutput $slog -RedirectStandardError ($slog + '.err')
if (-not $p2.WaitForExit(20000)) { try{$p2.Kill()}catch{}; Bad 'server log TIMEOUT' }
else {
  Get-Content $slog -EA SilentlyContinue | ForEach-Object { Info $_ }
  Ok 'server log listing done'
}

Write-Host ''
Write-Host '========== SUMMARY ==========' -ForegroundColor Cyan
if ($script:fail -eq 0) {
  Write-Host ('ALL CHECKS PASSED (0 failures)') -ForegroundColor Green
} else {
  Write-Host ('FAILURES=' + $script:fail) -ForegroundColor Red
}
exit $script:fail
