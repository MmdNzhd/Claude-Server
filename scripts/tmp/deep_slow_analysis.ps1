$ErrorActionPreference='Continue'
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')

Write-Host '========== A) LIVE STATE =========='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect' } |
  ForEach-Object {
    $age = ((Get-Date) - $_.CreationDate).TotalSeconds
    Write-Host ("PID={0} age_s={1:N0} {2}" -f $_.ProcessId, $age, $_.CommandLine.Substring(0,[Math]::Min(200,$_.CommandLine.Length)))
  }
$fi = Get-Item $today -EA SilentlyContinue
Write-Host ("log_size_MB={0:N2} mtime={1}" -f ($fi.Length/1MB), $fi.LastWriteTime)
$wm = $today + '.sync-offset'
Write-Host ('watermark=' + $(if(Test-Path $wm){(Get-Content $wm -Raw).Trim()}else{'MISSING'}))

Write-Host ''
Write-Host '========== B) ALL SESSIONS TODAY =========='
Select-String -Path $today -Pattern 'session start v' | ForEach-Object { $_.Line }

Write-Host ''
Write-Host '========== C) LATEST SESSION FULL PHASE BREAKDOWN =========='
$starts = @(Select-String -Path $today -Pattern 'session start v20')
if ($starts.Count -eq 0) { Write-Host 'no session'; exit 0 }
$lastStart = $starts[-1].Line
if ($lastStart -match 'session=([a-f0-9]+)') { $sid = $Matches[1] } else { $sid = $null }
Write-Host ("latest_sid=$sid")
Write-Host $lastStart

$sess = @(Select-String -Path $today -Pattern ("\[" + $sid + "\]") | ForEach-Object { $_.Line })
Write-Host ("session_lines=" + $sess.Count)

function Parse-Ts([string]$line) {
  if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]') {
    return [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
  }
  return $null
}

$t0 = Parse-Ts $sess[0]
$tLast = Parse-Ts $sess[-1]
if ($t0 -and $tLast) { Write-Host ("session_span_s={0:N1}" -f ($tLast-$t0).TotalSeconds) }

# Phase markers
$phases = @(
  @{n='session_start'; p='session start'},
  @{n='single_instance'; p='SINGLE_INSTANCE'},
  @{n='laptop_ssh_key'; p='STEP end: Laptop SSH key'},
  @{n='server_setup_begin'; p='STEP begin: Server setup'},
  @{n='first_ssh'; p='SSH_BEGIN'},
  @{n='tunnel_up'; p='TUNNEL_UP|tunnel ready|STEP end:.*[Tt]unnel|Ensure-SessionTunnel|tunnel:up'},
  @{n='mount'; p='STEP end:.*[Mm]ount|MOUNT_|Invoke-Mount'},
  @{n='auth'; p='AUTH: done|AUTH_DECISION|STEP end:.*[Aa]uth'},
  @{n='editor'; p='LAUNCH_|EDITOR_DECISION|STEP end:.*[Ee]ditor'},
  @{n='ready'; p='Session active|STATUS:.*tunnel:up'}
)

Write-Host ''
Write-Host '--- first hit of key phases ---'
foreach ($ph in $phases) {
  $hit = $sess | Where-Object { $_ -match $ph.p } | Select-Object -First 1
  if ($hit) {
    $ts = Parse-Ts $hit
    $delta = if ($t0 -and $ts) { '{0:N1}s' -f ($ts-$t0).TotalSeconds } else { '?' }
    $short = $hit; if ($short.Length -gt 160) { $short = $short.Substring(0,160) }
    Write-Host ("[+{0}] {1}: {2}" -f $delta, $ph.n, $short)
  } else {
    Write-Host ("[----] {0}: NOT REACHED" -f $ph.n)
  }
}

Write-Host ''
Write-Host '========== D) SSH COST BREAKDOWN (latest session) =========='
$sshEnds = @()
foreach ($line in $sess) {
  if ($line -match 'SSH_END exit=([-\d]+) ms=(\d+) out=(.*)$') {
    $ms = [int]$Matches[2]
    $out = $Matches[3]
    if ($out.Length -gt 60) { $out = $out.Substring(0,60) }
    # find preceding SSH_BEGIN cmd
    $sshEnds += [pscustomobject]@{ Ms=$ms; Exit=$Matches[1]; Out=$out; Line=$line }
  }
}
# pair with BEGIN for cmd
$begins = @($sess | Where-Object { $_ -match 'SSH_BEGIN cmd=(.+)$' })
Write-Host ("ssh_end_count=" + $sshEnds.Count)
Write-Host ("ssh_begin_count=" + $begins.Count)
if ($sshEnds.Count -gt 0) {
  $sum = ($sshEnds | Measure-Object -Property Ms -Sum).Sum
  $avg = ($sshEnds | Measure-Object -Property Ms -Average).Average
  $max = ($sshEnds | Measure-Object -Property Ms -Maximum).Maximum
  Write-Host ("ssh_sum_ms={0} ({1:N1}s) avg={2:N0} max={3}" -f $sum, ($sum/1000.0), $avg, $max)
}

Write-Host ''
Write-Host '--- each SSH call (BEGIN cmd + END ms) ---'
$bi = 0
for ($i=0; $i -lt $sess.Count; $i++) {
  if ($sess[$i] -match 'SSH_BEGIN cmd=(.+)$') {
    $cmd = $Matches[1]
    if ($cmd.Length -gt 90) { $cmd = $cmd.Substring(0,90) + '...' }
    $ms = '?'
    for ($j=$i+1; $j -lt [Math]::Min($i+5,$sess.Count); $j++) {
      if ($sess[$j] -match 'SSH_END exit=([-\d]+) ms=(\d+)') { $ms = $Matches[2]; break }
    }
    $cat = 'other'
    if ($cmd -match 'grep.*LAPTOP_|grep.*TUNNEL_|grep.*ACTIVE_|grep.*GIT_') { $cat = 'conf_grep' }
    elseif ($cmd -match 'claude_laptop|ssh-keygen|id -u') { $cat = 'key_setup' }
    elseif ($cmd -match 'fuser|pkill') { $cat = 'stale_kill' }
    elseif ($cmd -match '/dev/tcp|nc -w') { $cat = 'port_probe' }
    elseif ($cmd -match 'printf.*claude-connect.conf|PUSH|mkdir -p ~/.local') { $cat = 'push_conf' }
    elseif ($cmd -match 'claude-self-heal') { $cat = 'self_heal' }
    elseif ($cmd -match 'claude-mount|CM ') { $cat = 'mount' }
    elseif ($cmd -match 'cursor-auth|auth') { $cat = 'auth' }
    Write-Host ("  {0,5}ms  [{1,-11}] {2}" -f $ms, $cat, $cmd)
  }
}

# category totals
Write-Host ''
Write-Host '--- SSH ms by category ---'
$cats = @{}
for ($i=0; $i -lt $sess.Count; $i++) {
  if ($sess[$i] -match 'SSH_BEGIN cmd=(.+)$') {
    $cmd = $Matches[1]
    $ms = 0
    for ($j=$i+1; $j -lt [Math]::Min($i+5,$sess.Count); $j++) {
      if ($sess[$j] -match 'SSH_END exit=([-\d]+) ms=(\d+)') { $ms = [int]$Matches[2]; break }
    }
    $cat = 'other'
    if ($cmd -match 'grep.*LAPTOP_|grep.*TUNNEL_|grep.*ACTIVE_|grep.*GIT_|grep -E') { $cat = 'conf_grep' }
    elseif ($cmd -match 'claude_laptop|ssh-keygen|id -u') { $cat = 'key_setup' }
    elseif ($cmd -match 'fuser|pkill') { $cat = 'stale_kill' }
    elseif ($cmd -match '/dev/tcp|nc -w') { $cat = 'port_probe' }
    elseif ($cmd -match 'printf.*claude-connect|mkdir -p ~/.local/bin && printf') { $cat = 'push_conf' }
    elseif ($cmd -match 'claude-self-heal') { $cat = 'self_heal' }
    elseif ($cmd -match 'claude-mount') { $cat = 'mount' }
    if (-not $cats.ContainsKey($cat)) { $cats[$cat] = @{n=0;ms=0} }
    $cats[$cat].n++
    $cats[$cat].ms += $ms
  }
}
$cats.GetEnumerator() | Sort-Object { $_.Value.ms } -Descending | ForEach-Object {
  Write-Host ("  {0,-12} calls={1} total_ms={2} ({3:N1}s)" -f $_.Key, $_.Value.n, $_.Value.ms, ($_.Value.ms/1000.0))
}

Write-Host ''
Write-Host '========== E) PRE-SESSION (BOOTSTRAP/UPDATE) for last launch =========='
# find last BOOTSTRAP before this session
$allLines = Get-Content $today
$startIdx = -1
for ($i=$allLines.Count-1; $i -ge 0; $i--) {
  if ($allLines[$i] -match ("session=$sid") -or ($allLines[$i] -match "\[$sid\].*session start")) { $startIdx = $i; break }
}
$bootIdx = -1
if ($startIdx -gt 0) {
  for ($i=$startIdx; $i -ge [Math]::Max(0,$startIdx-80); $i--) {
    if ($allLines[$i] -match 'BOOTSTRAP:') { $bootIdx = $i; break }
  }
}
if ($bootIdx -ge 0 -and $startIdx -gt $bootIdx) {
  $tb = Parse-Ts $allLines[$bootIdx]
  $ts = Parse-Ts $allLines[$startIdx]
  Write-Host ("bootstrap_to_session_s={0:N1}" -f ($ts-$tb).TotalSeconds)
  for ($i=$bootIdx; $i -le $startIdx; $i++) {
    $l = $allLines[$i]
    if ($l -match 'BOOTSTRAP|UPDATE|session start') {
      Write-Host $l.Substring(0,[Math]::Min(220,$l.Length))
    }
  }
}

Write-Host ''
Write-Host '========== F) WHY ~1200ms PER SSH? sample Invoke-SshXCore =========='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'function Invoke-SshXCore|ControlMaster|ssh @|Start-Process.*ssh' -Context 0,12 |
  Select-Object -First 40 |
  ForEach-Object { $_.Line }

Write-Host ''
Write-Host '========== G) STALE/PORT LOOPS IN CODE (expected waits) =========='
Select-String -Path scripts\client\git-mode.ps1 -Pattern 'for \(\$i = 1; \$i -le|Start-Sleep -Milliseconds|Wait-ForTunnelUp|Clear-ServerStale' |
  Select-Object -First 25 |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
