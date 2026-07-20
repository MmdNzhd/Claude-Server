$ErrorActionPreference='Continue'
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')

Write-Host "=== live processes ==="
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.(ps1|bat)|connect-ui' } |
  ForEach-Object {
    $age=((Get-Date)-$_.CreationDate).TotalSeconds
    Write-Host ("PID={0} age_s={1:N0}" -f $_.ProcessId,$age)
    Write-Host ("  {0}" -f $_.CommandLine)
  }

function Ts([string]$line){
  if($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]'){ return [datetime]::ParseExact($Matches[1],'yyyy-MM-dd HH:mm:ss.fff',$null) }
  $null
}

foreach($sid in @('b25d17344291','45c2722335a7')){
  Write-Host "`n########## SESSION $sid ##########" -ForegroundColor Cyan
  $sess=@(Select-String -Path $today -Pattern ("\["+$sid+"\]") | ForEach-Object { $_.Line })
  if(-not $sess.Count){ Write-Host 'no lines'; continue }
  $t0=Ts $sess[0]; $tL=Ts $sess[-1]
  Write-Host ("lines={0} span_s={1:N1} first={2} last={3}" -f $sess.Count, $(if($t0 -and $tL){($tL-$t0).TotalSeconds}else{-1}), $sess[0].Substring(0,[Math]::Min(120,$sess[0].Length)), $sess[-1].Substring(0,[Math]::Min(120,$sess[-1].Length)))

  Write-Host '--- STEPs ---'
  $sess | Where-Object { $_ -match 'STEP (begin|end):|STATUS:|session start|TUNNEL: recovering|MOUNT_|GITMODE: MOUNT|DECISION: project|READY|Session active|HUNG|timeout' } |
    Where-Object { $_ -notmatch 'PERF\[' } |
    ForEach-Object { Write-Host $_.Substring(0,[Math]::Min(220,$_.Length)) }

  Write-Host '--- long SSH (>2s) + any incomplete ---'
  for($i=0;$i -lt $sess.Count;$i++){
    if($sess[$i] -match 'SSH_BEGIN cmd=(.+)$'){
      $cmd=$Matches[1]
      $ms=$null; $ex=$null
      for($j=$i+1;$j -lt [Math]::Min($i+15,$sess.Count);$j++){
        if($sess[$j] -match 'SSH_END exit=([-\d]+) ms=(\d+)'){ $ex=$Matches[1]; $ms=[int]$Matches[2]; break }
        if($sess[$j] -match 'SSH_BEGIN'){ break }
      }
      if($null -eq $ms){
        $ts=Ts $sess[$i]
        $age=if($ts){'{0:N0}' -f ((Get-Date)-$ts).TotalSeconds}else{'?'}
        Write-Host ("  HUNG age_s={0} {1}" -f $age, $cmd.Substring(0,[Math]::Min(180,$cmd.Length))) -ForegroundColor Red
      } elseif($ms -ge 2000){
        $c=$cmd; if($c.Length -gt 140){$c=$c.Substring(0,140)+'...'}
        Write-Host ("  {0,6}ms exit={1} {2}" -f $ms,$ex,$c)
      }
    }
  }

  # time between STEP begin Mounting and STEP end / next
  $mb=$sess | Where-Object { $_ -match 'STEP begin: Mounting' } | Select-Object -First 1
  $me=$sess | Where-Object { $_ -match 'STEP end: Mounting' } | Select-Object -First 1
  if($mb){
    $tb=Ts $mb; $te=if($me){Ts $me}else{$null}
    Write-Host ("MOUNT_STEP begin={0} end={1} dur_s={2}" -f $mb.Substring(0,30), $(if($me){$me.Substring(0,30)}else{'NONE'}), $(if($tb -and $te){'{0:N1}' -f ($te-$tb).TotalSeconds}else{'INCOMPLETE'}))
  }
}

# Any newer session after .21?
Write-Host "`n=== all session starts after 14:00 ==="
Select-String -Path $today -Pattern 'session start v' | Where-Object { $_.Line -match '14:' -or $_.Line -match '15:' } | ForEach-Object { $_.Line }

Write-Host "`n=== last 40 non-cim lines ==="
Get-Content $today -Tail 120 | Where-Object { $_ -notmatch 'PERF\[cim|TRACE' } | Select-Object -Last 40
