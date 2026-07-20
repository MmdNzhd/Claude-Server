$ErrorActionPreference='Continue'
$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$lines=Get-Content $log

function Slice([int]$from,[int]$to) {
  for ($i=$from; $i -le $to; $i++) {
    if ($i-ge 1 -and $i-le $lines.Count) { 'L{0}|{1}' -f $i, $lines[$i-1] }
  }
}

Write-Output '======== DROP1 FORENSIC 17:05:03..17:05:40 ========'
# Find last OK banner before drop1, ssh through 21003 success, cache, sync
Slice 60 70
Write-Output '--- diagnostic tunnel fields + ssh -p 21003 ---'
# extract key lines by regex in range
for ($i=150; $i -le 240; $i++) {
  $l=$lines[$i-1]
  if ($l -match 'TUNNEL up=|VERDICT_|CURSOR_ON|AUTH ok|MOUNT ok|SSH_RECENT|21003|TUNNEL_BANNER|TUNNEL_UP|TUNNEL_SYNC|connection dropped|RECOVERY_|PERF\[session|ssh_count|local_port') {
    'L{0}|{1}' -f $i, $l
  }
}

Write-Output ''
Write-Output '======== DROP2 FORENSIC: last 40s before 17:14:16 ========'
# find last successful banner before L12518
$lastOk=$null
for ($i=12518; $i -ge 12000; $i--) {
  if ($lines[$i-1] -match 'TUNNEL_BANNER port=21003 banner=SSH') { $lastOk=$i; break }
}
"last_ok_banner_line=$lastOk"
if ($lastOk) {
  $ts1= if($lines[$lastOk-1] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
  $ts2= if($lines[12517] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
  "last_ok_ts=$ts1 empty_ts=$ts2"
}
# count probes between last ok and empty
$probeN=0; $bgN=0
for ($i=$lastOk; $i -le 12521; $i++) {
  if ($lines[$i-1] -match 'TUNNEL_BANNER_BEGIN') { $probeN++ }
  if ($lines[$i-1] -match 'bg_alive') { $bgN++ }
}
"probes_since_ok=$probeN bg_alive_logs=$bgN"
Slice ($lastOk) ($lastOk+3)
Write-Output '--- immediate pre-drop2 ---'
for ($i=12510; $i -le 12535; $i++) { 'L{0}|{1}' -f $i, $lines[$i-1] }

Write-Output ''
Write-Output '======== DROP3 FORENSIC 18:08 ========'
$lastOk3=$null
for ($i=92113; $i -ge 91800; $i--) {
  if ($lines[$i-1] -match 'TUNNEL_BANNER port=21003 banner=SSH') { $lastOk3=$i; break }
}
"last_ok_banner_line=$lastOk3 line=$($lines[$lastOk3-1])"
# interval from last OK to empty
if ($lastOk3) {
  $tOk=[datetime]::ParseExact(($lines[$lastOk3-1] -replace '^\[([^\]]+)\].*','$1'),'yyyy-MM-dd HH:mm:ss.fff',$null)
  $tEmpty=[datetime]::ParseExact(($lines[92112] -replace '^\[([^\]]+)\].*','$1'),'yyyy-MM-dd HH:mm:ss.fff',$null)
  "gap_ms=$(($tEmpty-$tOk).TotalMilliseconds)"
}
for ($i=92100; $i -le 92170; $i++) {
  $l=$lines[$i-1]
  if ($l -match 'TUNNEL_|connection dropped|RECOVERY_|ssh_died|ENSURE_TUNNEL|STALE_|STEP end: Starting|PERF\[cim') {
    'L{0}|{1}' -f $i, $l
  }
}

Write-Output ''
Write-Output '======== PROBE CADENCE STATS (stable window 17:20-18:00) ========'
$begins=@()
foreach ($ln in $lines) {
  if ($ln -match '\[(2026-07-17 1[78]:[2-5]\d:[^\]]+)\] .*TUNNEL_BANNER_BEGIN') {
    try { $begins += [datetime]::ParseExact($matches[1],'yyyy-MM-dd HH:mm:ss.fff',$null) } catch {}
  }
}
if ($begins.Count -gt 2) {
  $gaps=@()
  for ($i=1; $i -lt $begins.Count; $i++) { $gaps += ($begins[$i]-$begins[$i-1]).TotalMilliseconds }
  $gaps = $gaps | Sort-Object
  "banner_begin_n=$($begins.Count)"
  "gap_ms_min=$([int]$gaps[0]) p50=$([int]$gaps[[int]($gaps.Count/2)]) p90=$([int]$gaps[[int]($gaps.Count*0.9)]) max=$([int]$gaps[-1])"
  "mean_ms=$([int](($gaps|Measure-Object -Average).Average))"
}

Write-Output ''
Write-Output '======== EMPTY BANNER CLASSIFICATION ========'
# classify each empty by exit/ms/bg
$n=0
foreach ($ln in $lines) {
  if ($ln -notmatch 'TUNNEL_BANNER port=21003 banner=$' -and $ln -notmatch 'TUNNEL_BANNER port=21003 banner=\s*$') { continue }
  # find line index
}
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -notmatch '\[DEBUG\] GITMODE: TUNNEL_BANNER port=21003 banner=(.*)$') { continue }
  $b=$matches[1]
  if ($b -ne '') { continue }
  $n++
  $sshEnd='?'
  for ($j=$i-1; $j -ge [Math]::Max(0,$i-6); $j--) {
    if ($lines[$j] -match 'SSH_END exit=(\S+) ms=(\d+) out=(.*)$') {
      $sshEnd="exit=$($matches[1]) ms=$($matches[2]) out=$($matches[3])"; break
    }
  }
  $bg='no_bg'
  for ($j=$i-1; $j -ge [Math]::Max(0,$i-8); $j--) {
    if ($lines[$j] -match 'bg_alive pid=(\d+)') { $bg="bg=$($matches[1])"; break }
  }
  $ts= if($lines[$i] -match '^\[([^\]]+)\]'){$matches[1]}else{''}
  $followed='none'
  for ($j=$i; $j -le [Math]::Min($lines.Count-1,$i+15); $j++) {
    if ($lines[$j] -match 'connection dropped') { $followed='DROP'; break }
    if ($lines[$j] -match 'VERDICT_CODE=TUNNEL_DOWN') { $followed='VERDICT_DOWN'; break }
    if ($lines[$j] -match 'TUNNEL_BANNER port=21003 banner=SSH') { $followed='recovered_ok'; break }
    if ($lines[$j] -match 'ENSURE_TUNNEL ok=1') { $followed='ensure_ok'; break }
  }
  'EMPTY#{0} L{1} {2} {3} {4} next={5}' -f $n,($i+1),$ts,$sshEnd,$bg,$followed
}

Write-Output ''
Write-Output '======== DROP1: was BgTunnel attached? pid 38352 after diag ===='
Select-String -Path $log -Pattern '38352|SessionBgTunnel|reattached|tunnel_down|bg_alive' |
  Where-Object { $_.LineNumber -ge 40 -and $_.LineNumber -le 250 } |
  ForEach-Object { 'L{0}|{1}' -f $_.LineNumber, $_.Line }
