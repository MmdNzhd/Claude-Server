$ErrorActionPreference='Continue'
Write-Host '=== SHA match ==='
$src=(Get-FileHash scripts\client\connect-ui.ps1 -Algorithm SHA256).Hash.Substring(0,16)
$dep=ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 'sha256sum /usr/local/share/claude-client/connect-ui.ps1' 
Write-Host "src=$src dep=$dep"

Write-Host '=== mac policy lines ==='
Select-String -Path scripts\client\connect-ui.sh -Pattern 'TRACE|ge 25|ge 1' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }

Write-Host '=== copy local (shared) ==='
$local=Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst=Join-Path $env:TEMP 'dl.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite'); $o=[IO.File]::Create($dst); $fs.CopyTo($o); $o.Close(); $fs.Close()
Write-Host "local=$((Get-Item $dst).Length)"

Write-Host '=== scp server ==='
$srv=Join-Path $env:TEMP 'ds.log'
scp -o BatchMode=yes -o ConnectTimeout=60 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srv
Write-Host "server=$((Get-Item $srv).Length) gap=$(( (Get-Item $dst).Length - (Get-Item $srv).Length ))"

# use findstr for speed
function Count-Pat($file,$pat){ (Select-String -Path $file -SimpleMatch $pat -ErrorAction SilentlyContinue | Measure-Object).Count }
$ms=@('BOOTSTRAP: connect.bat start','UPDATE:','======== session start','DECISION: project_select','SESSION_LOOP begin','LAUNCH begin','Connection dropped','LOG_SYNC_FAIL','EXIT_WAIT','VERIFY_PROBE','False')
Write-Host 'marker L/S'
foreach($m in $ms){ Write-Host ("{0,5} {1,5}  {2}" -f (Count-Pat $dst $m),(Count-Pat $srv $m),$m) }

Write-Host 'sessions L:'; Select-String -Path $dst -Pattern 'session start v' | % Line
Write-Host 'sessions S:'; Select-String -Path $srv -Pattern 'session start v' | % Line

Write-Host 'STEPs:'; Select-String -Path $dst -Pattern 'STEP end:' | Select -First 12 | % { $_.Line.Substring(0,[Math]::Min(140,$_.Line.Length)) }

# level counts via regex on raw - sample first 2MB server full, local may be huge - use stream
function LevelHist($file){
  $h=@{INFO=0;WARN=0;ERROR=0;DEBUG=0;TRACE=0}
  $reader=[IO.StreamReader]::new($file)
  try {
    while($null -ne ($line=$reader.ReadLine())){
      if($line -match '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]'){ $h[$Matches[1]]++ }
    }
  } finally { $reader.Close() }
  $h.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Host ("  {0}={1}" -f $_.Key,$_.Value) }
}
Write-Host 'levels L:'; LevelHist $dst
Write-Host 'levels S:'; LevelHist $srv

if(Test-Path ($local+'.sync-offset')){ Write-Host "wm=$(Get-Content ($local+'.sync-offset') -Raw) size=$((Get-Item $local).Length)" } else { Write-Host 'wm=MISSING' }

Write-Host '=== live sync ==='
. .\scripts\client\connect-ui.ps1
$t=Join-Path $env:TEMP 'stress.log'; Remove-Item $t,($t+'.sync-offset') -Force -EA SilentlyContinue
$tag="DEEPSTRESS_$(Get-Date -Format HHmmssfff)"
$script:Alias='smart@192.168.250.70'; $script:ConnectLogPath=$t; $script:ConnectSessionId='x'; $script:ConnectLogSyncOffset=0; $script:ConnectLogSyncFailLogged=$false
$script:ConnectLogWriter=[IO.StreamWriter]::new($t,$false,[Text.UTF8Encoding]::new($false)); $script:ConnectLogWriter.AutoFlush=$true
1..30|%{Write-ConnectLog "$tag $_" INFO}; Write-ConnectLog "$tag TRACE" TRACE; Write-ConnectLog "$tag WARN" WARN
$script:ConnectLogWriter.Close(); $script:ConnectLogWriter=$null
$leak=0; 1..2|%{$script:ConnectLogSyncOffset=0; if((Sync-ConnectLogToServer|Out-String).Trim()){$leak++}}
$c=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log").Trim()
Write-Host "LastOk=$($script:LastConnectLogSyncOk) leaks=$leak tag_count=$c"
Remove-Item $t,($t+'.sync-offset') -Force -EA SilentlyContinue

Write-Host '=== perf sample ==='
$cim=(Select-String -Path $dst -Pattern 'PERF\[cim_query\]' | Measure).Count
$stale=(Select-String -Path $dst -Pattern 'STALE_FORWARD|port still busy|ORPHAN_TUNNEL' | Measure).Count
Write-Host "cim=$cim stale=$stale"
Select-String -Path $dst -Pattern 'STALE_FORWARD|port still busy|ORPHAN_TUNNEL' | Select -First 5 | % { $_.Line.Substring(0,[Math]::Min(130,$_.Line.Length)) }
Write-Host "lines=$((Select-String -Path $dst -Pattern '.' | Measure).Count)"
Remove-Item $dst,$srv -Force -EA SilentlyContinue
Write-Host DONE
