$ErrorActionPreference='Continue'
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst = Join-Path $env:TEMP 's11-local.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite')
try{$o=[IO.File]::Create($dst);try{$fs.CopyTo($o)}finally{$o.Close()}}finally{$fs.Close()}
Write-Host ("local_bytes={0}" -f (Get-Item $dst).Length)
if(Test-Path ($local+'.sync-offset')){ Write-Host ("watermark={0} size={1}" -f (Get-Content ($local+'.sync-offset') -Raw).Trim(), (Get-Item $local).Length) } else { Write-Host 'watermark=MISSING' }

Write-Host '=== all sessions ==='
Select-String -Path $dst -Pattern 'session start v' | ForEach-Object { $_.Line.Substring(0,[Math]::Min(170,$_.Line.Length)) }

$last = Select-String -Path $dst -Pattern 'session start v20260719\.11.*session=([a-f0-9]+)' | Select-Object -Last 1
if(-not $last){ Write-Host 'NO .11 session'; Remove-Item $dst -Force; exit 1 }
$sid = $last.Matches[0].Groups[1].Value
Write-Host "SID=$sid"
Write-Host $last.Line

function Ts([string]$line){
  if($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.(\d{3})\]'){
    return [datetime]::ParseExact(($Matches[1]+'.'+$Matches[2]),'yyyy-MM-dd HH:mm:ss.fff',$null)
  }
  $null
}

Write-Host '=== STEP ends ==='
Select-String -Path $dst -Pattern "\[$sid\].*STEP end:" | ForEach-Object { $_.Line.Substring(0,[Math]::Min(165,$_.Line.Length)) }

Write-Host '=== DECISION / LAUNCH / LOOP / AUTH / MOUNT ==='
Select-String -Path $dst -Pattern "\[$sid\].*(DECISION:|SESSION_LOOP begin|LAUNCH begin|MOUNT:|AUTH:|server_ready|LOG_SYNC)" |
  Select-Object -First 40 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(160,$_.Line.Length)) }

$tStart = Ts $last.Line
$dec = Select-String -Path $dst -Pattern "\[$sid\].*DECISION: project_select" | Select-Object -First 1
$loop = Select-String -Path $dst -Pattern "\[$sid\].*SESSION_LOOP begin" | Select-Object -First 1
$launch = Select-String -Path $dst -Pattern "\[$sid\].*LAUNCH begin" | Select-Object -First 1
$ready = Select-String -Path $dst -Pattern "\[$sid\].*CONTEXT phase=server_ready" | Select-Object -First 1
Write-Host '=== durations from session start ==='
if($dec){ Write-Host ("to_decision_sec={0:N2}" -f ((Ts $dec.Line)-$tStart).TotalSeconds); Write-Host $dec.Line.Substring(0,120) }
if($loop){ Write-Host ("to_session_loop_sec={0:N2}" -f ((Ts $loop.Line)-$tStart).TotalSeconds) }
if($ready){ Write-Host ("to_server_ready_sec={0:N2}" -f ((Ts $ready.Line)-$tStart).TotalSeconds) }
if($launch){ Write-Host ("to_launch_sec={0:N2}" -f ((Ts $launch.Line)-$tStart).TotalSeconds) }

Write-Host '=== slow STEP details (ms=) ==='
Select-String -Path $dst -Pattern "\[$sid\].*STEP end:.*ms=" | ForEach-Object {
  if($_.Line -match 'ms=(\d+)'){ [pscustomobject]@{Ms=[int]$Matches[1]; Line=$_.Line.Substring(0,[Math]::Min(150,$_.Line.Length))} }
} | Sort-Object Ms -Descending | Select-Object -First 12 | ForEach-Object { '{0,6} ms | {1}' -f $_.Ms, $_.Line }

Write-Host '=== STALE/ORPHAN this sid ==='
Select-String -Path $dst -Pattern "\[$sid\].*(STALE|ORPHAN|port still busy)" | Select-Object -First 15 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(150,$_.Line.Length)) }

Write-Host '=== levels this sid ==='
$h=@{INFO=0;WARN=0;ERROR=0;DEBUG=0;TRACE=0}
$r=[IO.StreamReader]::new($dst)
try{ while($null -ne ($line=$r.ReadLine())){ if($line -notmatch "\[$sid\]"){continue}; if($line -match '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]'){ $h[$Matches[1]]++ } } } finally{$r.Close()}
$h.GetEnumerator()|Sort Value -Desc|%{ '{0}={1}' -f $_.Key,$_.Value }

$cim=@(Select-String -Path $dst -Pattern "\[$sid\].*PERF\[cim_query\] ms=(\d+)")
$ms=@($cim|%{ [int]$_.Matches[0].Groups[1].Value })
if($ms){ Write-Host ("cim_n={0} max={1} sum={2} gt0={3}" -f $cim.Count,($ms|Measure -Max).Maximum,($ms|Measure -Sum).Sum,(@($ms|?{$_ -gt 0}).Count)) }

Write-Host '=== LOG_SYNC_FAIL / False ==='
Write-Host ("LOG_SYNC_FAIL_n={0}" -f @(Select-String -Path $dst -SimpleMatch 'LOG_SYNC_FAIL').Count)
Write-Host ("False_literal_n={0}" -f @(Select-String -Path $dst -SimpleMatch '] False').Count)

# bootstrap near session
Write-Host '=== nearby BOOTSTRAP/UPDATE before session ==='
$idx = ($last.LineNumber)
Get-Content $dst | Select-Object -Skip ([Math]::Max(0,$idx-30)) -First 35 | Where-Object { $_ -match 'BOOTSTRAP|UPDATE:|session start' } | ForEach-Object { $_.Substring(0,[Math]::Min(150,$_.Length)) }

Write-Host '=== SERVER copy ==='
$srv=Join-Path $env:TEMP 's11-srv.log'
scp -o BatchMode=yes -o ConnectTimeout=45 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srv
Write-Host ("server_bytes={0} gap={1}" -f (Get-Item $srv).Length, ((Get-Item $dst).Length-(Get-Item $srv).Length))
Write-Host 'server sessions:'
Select-String -Path $srv -Pattern 'session start v' | Select-Object -Last 6 | %{ $_.Line.Substring(0,[Math]::Min(160,$_.Line.Length)) }
$ss=@(Select-String -Path $srv -Pattern "\[$sid\]")
Write-Host ("server_sid_lines={0}" -f $ss.Count)
if($ss.Count -gt 0){
  Write-Host ("srv_first: "+$ss[0].Line.Substring(0,[Math]::Min(140,$ss[0].Line.Length)))
  Write-Host ("srv_last:  "+$ss[-1].Line.Substring(0,[Math]::Min(140,$ss[-1].Line.Length)))
}
foreach($m in @('DECISION: project_select','SESSION_LOOP begin','LAUNCH begin','STEP end: Loading projects','STEP end: Server setup')){
  $a=@(Select-String -Path $dst -Pattern "\[$sid\].*$([regex]::Escape($m))").Count
  $b=@(Select-String -Path $srv -Pattern "\[$sid\].*$([regex]::Escape($m))").Count
  Write-Host ("sid marker {0}: L={1} S={2}" -f $m,$a,$b)
}
Remove-Item $dst,$srv -Force -EA SilentlyContinue
Write-Host DONE
