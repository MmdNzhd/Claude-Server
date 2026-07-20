$ErrorActionPreference='Continue'
$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
if (-not (Test-Path $log)) {
  # try latest connect.log near scripts
  $cands = @(
    'scripts\client\windows\connect.log',
    "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log"
  )
  foreach ($c in $cands) { if (Test-Path $c) { $log=$c; break } }
}
Write-Output "LOG=$log"
Write-Output "SIZE=$((Get-Item $log).Length) MTIME=$((Get-Item $log).LastWriteTime)"

$lines = Get-Content $log
Write-Output "LINES=$($lines.Count)"

# Classify every TUNNEL_BANNER (non-cache) result
$bannerLines = for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '\[DEBUG\] GITMODE: TUNNEL_BANNER port=(\d+) banner=(.*)$') {
    [pscustomobject]@{ Line=$i+1; Port=$matches[1]; Banner=$matches[2]; Raw=$lines[$i]; Ts= if ($lines[$i] -match '^\[([^\]]+)\]'){$matches[1]}else{''} }
  }
}
$ok = @($bannerLines | Where-Object { $_.Banner -match '^SSH-2\.0-' })
$empty = @($bannerLines | Where-Object { -not $_.Banner -or $_.Banner -eq '' })
$other = @($bannerLines | Where-Object { $_.Banner -and $_.Banner -notmatch '^SSH-2\.0-' })
Write-Output ""
Write-Output "==== BANNER PROBE COUNTS (fresh, not cache) ===="
Write-Output "total=$($bannerLines.Count) ok_ssh=$($ok.Count) empty=$($empty.Count) other=$($other.Count)"
if ($other.Count -gt 0) {
  Write-Output 'OTHER samples:'
  $other | Select-Object -First 10 | ForEach-Object { "L$($_.Line) banner=$($_.Banner)" }
}
Write-Output 'OK banner samples:'
$ok | Select-Object -First 5 | ForEach-Object { "L$($_.Line) banner=$($_.Banner)" }

# Duration of empty probes (SSH_END ms preceding)
Write-Output ""
Write-Output "==== EMPTY BANNER: preceding SSH_END timing ===="
foreach ($e in ($empty | Select-Object -First 15)) {
  $prev = $null
  for ($j=$e.Line-2; $j -ge [Math]::Max(0,$e.Line-8); $j--) {
    if ($lines[$j] -match 'SSH_END exit=(\S+) ms=(\d+)') {
      $prev = "exit=$($matches[1]) ms=$($matches[2])"
      break
    }
  }
  # was bg_alive just before?
  $bg=''
  for ($j=$e.Line-2; $j -ge [Math]::Max(0,$e.Line-6); $j--) {
    if ($lines[$j] -match 'bg_alive') { $bg='bg_alive=1'; break }
  }
  "L$($_.Line) ts=$($e.Ts) $prev $bg"
}

# Fix the foreach bug - use $e
Write-Output ""
Write-Output "==== EMPTY BANNER detail (first 20) ===="
$n=0
foreach ($e in $empty) {
  $n++; if ($n -gt 20) { break }
  $prev = '?'
  for ($j=$e.Line-2; $j -ge [Math]::Max(0,$e.Line-10); $j--) {
    if ($lines[$j] -match 'SSH_END exit=(\S+) ms=(\d+)\s+out=(.*)$') {
      $prev = "exit=$($matches[1]) ms=$($matches[2]) out=$($matches[3])"
      break
    }
  }
  $bg='bg=0'
  for ($j=$e.Line-2; $j -ge [Math]::Max(0,$e.Line-8); $j--) {
    if ($lines[$j] -match 'bg_alive pid=(\d+)') { $bg="bg=$($matches[1])"; break }
  }
  "L$($e.Line) $($e.Ts) $prev $bg"
}

# Sequence: how often empty banner is followed within 2s by drop/recovery
Write-Output ""
Write-Output "==== EMPTY -> DROP within 5 lines ===="
$fp=0
foreach ($e in $empty) {
  $window = $lines[($e.Line-1)..([Math]::Min($lines.Count-1,$e.Line+8))] -join "`n"
  if ($window -match 'connection dropped') { $fp++ }
}
Write-Output "empty_banners=$($empty.Count) led_to_drop_soon=$fp"

# Success streak between drops
Write-Output ""
Write-Output "==== Timeline of drops vs ok banners ===="
$events = @()
foreach ($o in $ok) { $events += [pscustomobject]@{T=$o.Ts; Kind='OK'; L=$o.Line} }
foreach ($e in $empty) { $events += [pscustomobject]@{T=$e.Ts; Kind='EMPTY'; L=$e.Line} }
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'connection dropped') {
    $ts= if ($lines[$i] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
    $events += [pscustomobject]@{T=$ts; Kind='DROP'; L=$i+1}
  }
  if ($lines[$i] -match 'ENSURE_TUNNEL ok=1') {
    $ts= if ($lines[$i] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
    $events += [pscustomobject]@{T=$ts; Kind='UP'; L=$i+1}
  }
  if ($lines[$i] -match 'VERDICT_CODE=TUNNEL_DOWN') {
    $ts= if ($lines[$i] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
    $events += [pscustomobject]@{T=$ts; Kind='VERDICT_DOWN'; L=$i+1}
  }
  if ($lines[$i] -match 'CURSOR_ON_FOLDER_OK') {
    $ts= if ($lines[$i] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
    $events += [pscustomobject]@{T=$ts; Kind='CURSOR_OK'; L=$i+1}
  }
}
$events | Sort-Object L | ForEach-Object { "$($_.T) L$($_.L) $($_.Kind)" } | Select-Object -First 80

Write-Output ""
Write-Output "==== OpenSSH_for_Windows match strictness ===="
$ok | ForEach-Object { $_.Banner } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "$($_.Count) x $($_.Name)" }

Write-Output ""
Write-Output "==== SSH storm around first drop (17:05:22) ===="
$sshBegin=0; $sshEnd=0
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '2026-07-17 17:05:') {
    if ($lines[$i] -match 'SSH_BEGIN') { $sshBegin++ }
    if ($lines[$i] -match 'SSH_END') { $sshEnd++ }
  }
}
"in 17:05 minute: SSH_BEGIN=$sshBegin SSH_END=$sshEnd"

Write-Output ""
Write-Output "==== Concurrent SSH_BEGIN without END (overlap heuristic) ===="
# parse timestamps of SSH_BEGIN/END in window 17:05:00-17:06:00
$stack=0; $max=0; $atMax=''
foreach ($ln in $lines) {
  if ($ln -notmatch '\[2026-07-17 17:05:') { continue }
  if ($ln -match 'SSH_BEGIN') { $stack++; if ($stack -gt $max) { $max=$stack; $atMax=$ln.Substring(0,[Math]::Min(40,$ln.Length)) } }
  if ($ln -match 'SSH_END') { if ($stack -gt 0){$stack--} }
}
"max_concurrent_approx=$max near=$atMax"

Write-Output ""
Write-Output "==== Port open vs banner empty (STALE_FORWARD zombie) ===="
Select-String -Path $log -Pattern 'zombie port|STALE_FORWARD: port still busy|foreign banner|bg_alive_forward_dead' |
  ForEach-Object { $_.Line } | Select-Object -First 40

Write-Output ""
Write-Output "==== Session version + how many recoveries ===="
Select-String -Path $log -Pattern 'version=2026|RECOVERY_BEGIN|ConnectVersion|CONNECT start' |
  Select-Object -First 20 | ForEach-Object { $_.Line }
$rec = @(Select-String -Path $log -Pattern 'RECOVERY_BEGIN')
"recovery_count=$($rec.Count)"
$rec | ForEach-Object { $_.Line }
