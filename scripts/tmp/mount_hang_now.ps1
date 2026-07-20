$ErrorActionPreference='Continue'
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
$fi=Get-Item $today
Write-Host ("log size_MB={0:N2} mtime={1}" -f ($fi.Length/1MB), $fi.LastWriteTime)

Write-Host "`n=== processes ==="
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.ps1' } |
  ForEach-Object {
    Write-Host ("PID={0} age_s={1:N0} {2}" -f $_.ProcessId, ((Get-Date)-$_.CreationDate).TotalSeconds, $_.CommandLine.Substring(0,[Math]::Min(180,$_.CommandLine.Length)))
  }

Write-Host "`n=== last 6 session starts ==="
Select-String -Path $today -Pattern 'session start v' | Select-Object -Last 6 | ForEach-Object { $_.Line }

$starts=@(Select-String -Path $today -Pattern 'session start v20')
$sid=$null
if($starts.Count -and $starts[-1].Line -match '\[([a-f0-9]{12})\]'){ $sid=$Matches[1] }
elseif($starts.Count -and $starts[-1].Line -match 'session=([a-f0-9]+)'){ $sid=$Matches[1] }
Write-Host "latest_sid=$sid ver_line=$($starts[-1].Line.Substring(0,[Math]::Min(160,$starts[-1].Line.Length)))"

function Ts([string]$line){
  if($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]'){ return [datetime]::ParseExact($Matches[1],'yyyy-MM-dd HH:mm:ss.fff',$null) }
  $null
}

# Analyze last 2 sessions for mount
$sids=@()
foreach($s in ($starts | Select-Object -Last 3)){
  if($s.Line -match '\[([a-f0-9]{12})\]'){ $sids += $Matches[1] }
}

foreach($sid in $sids){
  Write-Host "`n########## SESSION $sid ##########" -ForegroundColor Cyan
  $sess=@(Select-String -Path $today -Pattern ("\["+$sid+"\]") | ForEach-Object { $_.Line })
  $t0=Ts $sess[0]; $tL=Ts $sess[-1]
  Write-Host ("lines={0} span_s={1:N1}" -f $sess.Count, $(if($t0 -and $tL){($tL-$t0).TotalSeconds}else{-1}))

  # key phases with deltas
  $markers=@(
    @{n='start'; r='session start'},
    @{n='tunnelish'; r='TUNNEL_UP|Ensure-SessionTunnel|tunnel ready|STEP end:.*[Tt]unnel|BgTunnel|port=210'},
    @{n='mount_begin'; r='STEP begin:.*[Mm]ount|Invoke-Mount|claude-mount|MOUNT_'},
    @{n='mount_end'; r='STEP end:.*[Mm]ount|MOUNT_OK|mount ok|mounted'},
    @{n='auth'; r='AUTH: done|STEP end:.*[Aa]uth'},
    @{n='editor'; r='LAUNCH_|EDITOR_DECISION|STEP end:.*[Ee]ditor'},
    @{n='ready'; r='STATUS:.*tunnel:up|Session active'}
  )
  foreach($m in $markers){
    $hit=$sess | Where-Object { $_ -match $m.r } | Select-Object -First 1
    if($hit){
      $ts=Ts $hit
      $d=if($t0 -and $ts){'{0:N1}' -f ($ts-$t0).TotalSeconds}else{'?'}
      Write-Host ("[+{0}s] {1}: {2}" -f $d,$m.n, $hit.Substring(0,[Math]::Min(180,$hit.Length)))
    } else {
      Write-Host ("[----] {0}: NOT SEEN" -f $m.n)
    }
  }

  Write-Host '--- mount-related lines ---'
  $sess | Where-Object { $_ -match '(?i)mount|claude-mount|git hide|\.git|STEP .*[Mm]ount|Invoke-Mount|CM up|CM check' } |
    Where-Object { $_ -notmatch 'PERF\[' } |
    ForEach-Object { Write-Host $_.Substring(0,[Math]::Min(260,$_.Length)) }

  Write-Host '--- SSH calls >3s or mount cmds ---'
  for($i=0;$i -lt $sess.Count;$i++){
    if($sess[$i] -match 'SSH_BEGIN cmd=(.+)$'){
      $cmd=$Matches[1]
      $ms='?'; $ex='?'
      for($j=$i+1;$j -lt [Math]::Min($i+10,$sess.Count);$j++){
        if($sess[$j] -match 'SSH_END exit=([-\d]+) ms=(\d+)'){ $ex=$Matches[1]; $ms=$Matches[2]; break }
        if($sess[$j] -match 'SSH_BEGIN'){ break }
      }
      $interesting = ($ms -ne '?' -and [int]$ms -ge 3000) -or ($cmd -match 'mount|claude-mount|CM |git|\.git')
      if($interesting){
        $c=$cmd; if($c.Length -gt 130){$c=$c.Substring(0,130)+'...'}
        $pending = if($ms -eq '?'){' << NO SSH_END YET (HUNG?)'}else{''}
        Write-Host ("  {0,6}ms exit={1}{3} {2}" -f $ms,$ex,$c,$pending)
      }
    }
  }

  # detect hung: last SSH_BEGIN without END
  for($i=$sess.Count-1;$i -ge 0;$i--){
    if($sess[$i] -match 'SSH_BEGIN cmd=(.+)$'){
      $cmd=$Matches[1]
      $hasEnd=$false
      for($j=$i+1;$j -lt $sess.Count;$j++){
        if($sess[$j] -match 'SSH_END'){ $hasEnd=$true; break }
        if($sess[$j] -match 'SSH_BEGIN'){ break }
      }
      if(-not $hasEnd){
        $ts=Ts $sess[$i]
        $hung=if($ts){'{0:N0}' -f ((Get-Date)-$ts).TotalSeconds}else{'?'}
        Write-Host ("HUNG_SSH age_s={0} cmd={1}" -f $hung, $cmd.Substring(0,[Math]::Min(200,$cmd.Length))) -ForegroundColor Red
      }
      break
    }
  }
}

Write-Host "`n=== last 20 non-PERF lines overall ==="
Get-Content $today -Tail 80 | Where-Object { $_ -notmatch 'PERF\[cim' } | Select-Object -Last 20
