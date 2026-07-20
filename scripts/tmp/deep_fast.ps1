$ErrorActionPreference='Continue'
Write-Host 'Smart ver:' (ssh -o BatchMode=yes -o ConnectTimeout=6 -o ControlMaster=no smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt')
Write-Host 'src sha:' (Get-FileHash scripts\client\connect-ui.ps1 -Algorithm SHA256).Hash.Substring(0,16)

# mac policy snippet
Write-Host '--- mac connect_log ---'
Get-Content scripts\client\connect-ui.sh | Select-Object -Skip 200 -First 40 | ForEach-Object { $_ }

# copy local log with share
$local=Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst=Join-Path $env:TEMP 'dl.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite'); $o=[IO.File]::Create($dst); $fs.CopyTo($o); $o.Close(); $fs.Close()
Write-Host 'local bytes' (Get-Item $dst).Length 'lines' (Get-Content $dst|Measure).Count

$srv=Join-Path $env:TEMP 'ds.log'
scp -o BatchMode=yes -o ConnectTimeout=60 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srv
Write-Host 'server bytes' (Get-Item $srv).Length

$markers=@('BOOTSTRAP: connect.bat start','UPDATE:','======== session start','DECISION: project_select','SESSION_LOOP begin','LAUNCH begin','Connection dropped','LOG_SYNC_FAIL','EXIT_WAIT','VERIFY_PROBE','False')
foreach($m in $markers){
  $a=@(Select-String -Path $dst -SimpleMatch $m).Count
  $b=@(Select-String -Path $srv -SimpleMatch $m).Count
  Write-Host ("{0,6} {1,6}  {2}" -f $a,$b,$m)
}
Write-Host 'sessions local:'; Select-String -Path $dst -Pattern 'session start v' | % { $_.Line.Substring(0,[Math]::Min(110,$_.Line.Length)) }
Write-Host 'sessions server:'; Select-String -Path $srv -Pattern 'session start v' | % { $_.Line.Substring(0,[Math]::Min(110,$_.Line.Length)) }

Write-Host 'STEP ends:'; Select-String -Path $dst -Pattern 'STEP end:' | Select -First 15 | % { $_.Line.Substring(0,[Math]::Min(130,$_.Line.Length)) }

Write-Host 'levels L:'; Select-String -Path $dst -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | % Matches | % Groups | ?{$_.Name -eq '1'} | % Value | Group | Sort Count -Desc | % {"$($_.Name)=$($_.Count)"}
Write-Host 'levels S:'; Select-String -Path $srv -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | % Matches | % Groups | ?{$_.Name -eq '1'} | % Value | Group | Sort Count -Desc | % {"$($_.Name)=$($_.Count)"}

$wm=$local+'.sync-offset'
if(Test-Path $wm){Write-Host "wm=$(Get-Content $wm -Raw) size=$((Get-Item $local).Length)"} else {Write-Host 'wm=MISSING'}

# live sync short
. .\scripts\client\connect-ui.ps1
$t=Join-Path $env:TEMP 'stress.log'
$tag="DEEPSTRESS_$(Get-Date -Format HHmmssfff)"
$script:Alias='smart@192.168.250.70'; $script:ConnectLogPath=$t; $script:ConnectSessionId='x'; $script:ConnectLogSyncOffset=0
$script:ConnectLogWriter=[IO.StreamWriter]::new($t,$false,[Text.UTF8Encoding]::new($false)); $script:ConnectLogWriter.AutoFlush=$true
1..30|%{Write-ConnectLog "$tag $_" INFO}; Write-ConnectLog "$tag TRACE" TRACE; Write-ConnectLog "$tag WARN" WARN
$script:ConnectLogWriter.Close(); $script:ConnectLogWriter=$null
$leak=0; 1..2|%{$script:ConnectLogSyncOffset=0; if((Sync-ConnectLogToServer|Out-String).Trim()){$leak++}}
$c=ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log"
Write-Host "sync LastOk=$($script:LastConnectLogSyncOk) leaks=$leak server_tag_count=$c"
Remove-Item $t,($t+'.sync-offset'),$dst,$srv -Force -EA SilentlyContinue

# perf
$dst2=Join-Path $env:TEMP 'dl2.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite'); $o=[IO.File]::Create($dst2); $fs.CopyTo($o); $o.Close(); $fs.Close()
$cim=@(Select-String -Path $dst2 -Pattern 'PERF\[cim_query\]')
$stale=@(Select-String -Path $dst2 -Pattern 'STALE_FORWARD|port still busy|ORPHAN')
Write-Host "cim=$($cim.Count) stale=$($stale.Count) lines=$((Get-Content $dst2|Measure).Count)"
$stale|Select -First 4|%{Write-Host $_.Line.Substring(0,[Math]::Min(120,$_.Line.Length))}
Remove-Item $dst2 -Force -EA SilentlyContinue
Write-Host DONE
