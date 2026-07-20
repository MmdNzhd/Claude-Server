$ErrorActionPreference='Continue'
$rep = New-Object System.Collections.Generic.List[string]
function Rep([string]$s){ $script:rep.Add($s); Write-Host $s }

Rep '======== 1. SOURCE ========'
$ui = Get-Content 'scripts\client\connect-ui.ps1' -Raw
$nSync = ([regex]::Matches($ui,'(?m)^function Sync-ConnectLogToServer\b')).Count
$nInit = ([regex]::Matches($ui,'(?m)^function Initialize-ConnectLog\b')).Count
$nWL   = ([regex]::Matches($ui,'(?m)^function Write-ConnectLog\b')).Count
Rep ("Sync={0} Init={1} Write-ConnectLog={2}" -f $nSync,$nInit,$nWL)

$s0=$ui.IndexOf('function Sync-ConnectLogToServer'); $s1=$ui.IndexOf('function Write-ConnectLog {',$s0)
$sync=$ui.Substring($s0,$s1-$s0)
$w0=$ui.IndexOf('function Write-ConnectLog {'); $w1=$ui.IndexOf('function Read-ConnectPrompt',$w0)
$wl=$ui.Substring($w0,$w1-$w0)

$checks=@(
  @{n='Sync no bool return'; ok=($sync -notmatch 'return \$false|return \$true|return \$scpOk')},
  @{n='LastConnectLogSyncOk'; ok=($sync -match 'LastConnectLogSyncOk')},
  @{n='ControlMaster=no'; ok=($sync -match 'ControlMaster=no')},
  @{n='watermark'; ok=($sync -match 'Write-ConnectLogSyncWatermark')},
  @{n='LOG_SYNC_FAIL'; ok=($sync -match 'LOG_SYNC_FAIL')},
  @{n='HOME concat safe'; ok=($sync -match "\`$cat = 'cat")},
  @{n='mtime +1 cleanup'; ok=($sync -match 'mtime \+1')},
  @{n='TRACE skip'; ok=($wl -match "Level -eq 'TRACE'")},
  @{n='DEBUG skip'; ok=($wl -match "Level -eq 'DEBUG'")},
  @{n='batch 25'; ok=($wl -match '-ge 25')},
  @{n='WARN flush'; ok=($wl -match "Level -eq 'WARN'")}
)
foreach($c in $checks){ Rep ("  [{0}] {1}" -f ($(if($c.ok){'OK'}else{'FAIL'})), $c.n) }

Rep 'Call sites:'
Select-String -Path scripts\client\connect-ui.ps1,scripts\client\windows\connect.ps1 -Pattern 'Sync-ConnectLogToServer' |
  ForEach-Object { Rep ("  {0}:{1} {2}" -f ($_.Filename), $_.LineNumber, $_.Line.Trim()) }

Rep '======== 2. MAC PARITY ========'
$sh = Get-Content 'scripts\client\connect-ui.sh' -Raw
# extract sync function
if ($sh -match '(?s)sync_connect_log_to_server\(\)\s*\{(.*?)^\}') {
  $msb = $Matches[1]
  Rep ("  mac sync len={0}" -f $msb.Length)
  Rep ("  [{0}] HOME literal (not expanded)" -f ($(if($msb -match '\$HOME' -and $msb -notmatch 'C:Users'){'OK'}else{'CHECK'})))
  Rep ("  [{0}] watermark" -f ($(if($sh -match 'sync-offset'){'OK'}else{'FAIL'})))
  Rep ("  [{0}] TRACE/DEBUG skip or level gate" -f ($(if($sh -match 'TRACE|DEBUG|level'){'OK'}else{'FAIL'})))
}
# show connect_log policy
Select-String -Path scripts\client\connect-ui.sh -Pattern 'sync_connect|TRACE|DEBUG|lines_since|WARN|ge 25|every' |
  Select-Object -First 40 | ForEach-Object { Rep ("  sh L{0}: {1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(110,$_.Line.Trim().Length))) }

Rep '======== 3. DEPLOYED ========'
$srcHash=(Get-FileHash scripts\client\connect-ui.ps1 -Algorithm SHA256).Hash
$verSrc=(Get-Content scripts\client\windows\connect-version.txt -Raw).Trim()
Rep ("src sha={0} ver={1}" -f $srcHash.Substring(0,16), $verSrc)

# write remote check script and scp+run
$remotePy = @'
from pathlib import Path
t=Path("/usr/local/share/claude-client/connect-ui.ps1").read_text(errors="replace")
print("ver", Path("/usr/local/share/claude-client/connect-version.txt").read_text().strip())
print("sha", __import__("hashlib").sha256(t.encode()).hexdigest()[:16])
print("dup_sync", t.count("function Sync-ConnectLogToServer"))
s=t.find("function Sync-ConnectLogToServer"); e=t.find("function Write-ConnectLog", s); b=t[s:e]
print("bool", [x for x in ("return $false","return $true","return $scpOk") if x in b] or "NONE")
print("LastOk", "LastConnectLogSyncOk" in b)
print("home_safe", "$cat = 'cat" in b)
print("fail_log", "LOG_SYNC_FAIL" in b)
w=t[t.find("function Write-ConnectLog"):t.find("function Read-ConnectPrompt")]
print("skip_trace", "Level -eq 'TRACE'" in w)
print("batch25", "-ge 25" in w)
cp=Path("/usr/local/share/claude-client/connect.ps1").read_text(errors="replace")
print("bad_msg", "same folder as connect.bat" in cp)
print("good_msg", "ConnectLogPath" in cp)
# mac sh
sh=Path("/usr/local/share/claude-client/connect-ui.sh").read_text(errors="replace")
print("mac_sync", "sync_connect_log_to_server" in sh)
print("mac_watermark", "sync-offset" in sh)
'@
$pyLocal = Join-Path $env:TEMP 'deep_remote_check.py'
Set-Content $pyLocal $remotePy -Encoding ascii
scp -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no -q $pyLocal smart@192.168.250.70:/tmp/deep_remote_check.py
$remoteOut = ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 'python3 /tmp/deep_remote_check.py; rm -f /tmp/deep_remote_check.py'
$remoteOut -split "`n" | ForEach-Object { Rep ("  remote: $_") }
$smartV = (ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
Rep ("Smart frozen={0}" -f $smartV)
if ($srcHash.Substring(0,16) -eq (($remoteOut | Select-String '^sha ').ToString() -replace 'sha ','').Trim()) {
  Rep '  [OK] source sha matches deployed'
} else {
  # parse sha line
  $rsha = ($remoteOut -split "`n" | Where-Object { $_ -match '^sha ' } | Select-Object -First 1)
  Rep ("  [COMPARE] src={0} deployed={1}" -f $srcHash.Substring(0,16), $rsha)
}

Rep '======== 4. LOCAL vs SERVER LOG ========'
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst = Join-Path $env:TEMP 'deep-local.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite')
try{$o=[IO.File]::Create($dst);try{$fs.CopyTo($o)}finally{$o.Close()}}finally{$fs.Close()}
$srv=Join-Path $env:TEMP 'deep-server.log'
scp -o BatchMode=yes -o ConnectTimeout=60 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srv
Rep ("local={0} server={1} gap={2}" -f (Get-Item $dst).Length, (Get-Item $srv).Length, ((Get-Item $dst).Length-(Get-Item $srv).Length))

$markers=@('BOOTSTRAP: connect.bat start','UPDATE:','======== session start','DECISION: project_select','STEP end: Server setup','STEP end: Loading projects','SESSION_LOOP begin','STEP end: Mounting files','LAUNCH begin','Connection dropped','LOG_SYNC_FAIL','EXIT_WAIT','VERIFY_PROBE','False')
Rep 'markers local | server'
foreach($m in $markers){
  $a=@(Select-String -Path $dst -SimpleMatch $m).Count
  $b=@(Select-String -Path $srv -SimpleMatch $m).Count
  $flag = if($a -eq $b){'='} elseif($b -eq 0 -and $a -gt 0){'SERVER_MISS'} elseif($a -gt $b){'SERVER_BEHIND'} else {'SERVER_EXTRA'}
  Rep ("  [{0,-12}] L={1,5} S={2,5} {3}" -f $flag,$a,$b,$m)
}

Rep 'sessions:'
Select-String -Path $dst -Pattern 'session start v([0-9.]+).*session=([a-f0-9]+)' | ForEach-Object {
  Rep ("  LOCAL  {0} v{1} @ {2}" -f $_.Matches[0].Groups[2].Value, $_.Matches[0].Groups[1].Value, $_.Line.Substring(1,23))
}
Select-String -Path $srv -Pattern 'session start v([0-9.]+).*session=([a-f0-9]+)' | ForEach-Object {
  Rep ("  SERVER {0} v{1} @ {2}" -f $_.Matches[0].Groups[2].Value, $_.Matches[0].Groups[1].Value, $_.Line.Substring(1,23))
}

Rep 'STEP timeline (local first 20 STEP end):'
Select-String -Path $dst -Pattern 'STEP end:' | Select-Object -First 20 | ForEach-Object {
  Rep ("  {0}" -f $_.Line.Substring(0,[Math]::Min(150,$_.Line.Length)))
}

Rep 'levels local:'
Select-String -Path $dst -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | % {$_.Matches} | % {$_.Groups[1].Value} |
  Group-Object | Sort Count -Desc | % { Rep ("  {0}={1}" -f $_.Name,$_.Count) }
Rep 'levels server:'
Select-String -Path $srv -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | % {$_.Matches} | % {$_.Groups[1].Value} |
  Group-Object | Sort Count -Desc | % { Rep ("  {0}={1}" -f $_.Name,$_.Count) }

# byte prefix compare (strip BOM)
function StripBom([byte[]]$b){ if($b.Length-ge3 -and $b[0]-eq0xEF -and $b[1]-eq0xBB -and $b[2]-eq0xBF){ $n=New-Object byte[] ($b.Length-3); [Array]::Copy($b,3,$n,0,$n.Length); return $n }; return $b }
$lb=StripBom ([IO.File]::ReadAllBytes($dst))
$sb=StripBom ([IO.File]::ReadAllBytes($srv))
$same=$true; $n=[Math]::Min(65536,$sb.Length,[Math]::Min($lb.Length,$sb.Length))
for($i=0;$i -lt $n;$i++){ if($lb[$i]-ne $sb[$i]){ $same=$false; Rep ("first_diff@{0}" -f $i); break } }
Rep ("server_prefix_of_local_64k={0}" -f $same)

# Is server content contained? check BOOTSTRAP line equality
$l1=(Get-Content $dst -TotalCount 3)
$s1=(Get-Content $srv -TotalCount 3)
Rep ("local_l1={0}" -f $l1[0].Substring(0,[Math]::Min(100,$l1[0].Length)))
Rep ("server_l1={0}" -f $s1[0].Substring(0,[Math]::Min(100,$s1[0].Length)))

$wm=$local+'.sync-offset'
if(Test-Path $wm){ Rep ("watermark={0} filesize={1}" -f (Get-Content $wm -Raw).Trim(), (Get-Item $local).Length) } else { Rep 'watermark=MISSING' }

Rep '======== 5. LIVE SYNC ========'
. .\scripts\client\connect-ui.ps1
$tfile=Join-Path (Split-Path $local) 'deep-sync-stress.log'
Remove-Item $tfile,($tfile+'.sync-offset') -Force -EA SilentlyContinue
$script:Alias='smart@192.168.250.70'
$script:ConnectLogPath=$tfile
$script:ConnectSessionId='deepstress'
$script:ConnectLogSyncOffset=0
$script:ConnectLogSyncFailLogged=$false
$script:ConnectLogWriter=[IO.StreamWriter]::new($tfile,$true,[Text.UTF8Encoding]::new($false))
$script:ConnectLogWriter.AutoFlush=$true
$tag="DEEPSTRESS_{0}" -f (Get-Date -Format 'HHmmssfff')
1..30 | % { Write-ConnectLog "$tag line=$_" 'INFO' }
Write-ConnectLog "$tag TRACE_ONLY" 'TRACE'
Write-ConnectLog "$tag WARN_FLUSH" 'WARN'
$script:ConnectLogWriter.Close(); $script:ConnectLogWriter=$null
$leaks=@()
1..3 | % { $script:ConnectLogSyncOffset=0; $o=Sync-ConnectLogToServer|Out-String; if($o.Trim()){ $leaks += $o.Trim() } }
$g=ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log; grep -c '${tag} TRACE_ONLY' ~/.claude/logs/connect-20260719.log || true; grep '$tag WARN_FLUSH' ~/.claude/logs/connect-20260719.log | tail -1"
Rep ("stress: LastOk={0} leaks={1} grep={2}" -f $script:LastConnectLogSyncOk, $leaks.Count, ($g -replace "`n",' | '))
Remove-Item $tfile,($tfile+'.sync-offset') -Force -EA SilentlyContinue

Rep '======== 6. PERF ROOT CAUSE ========'
$cim=@(Select-String -Path $dst -Pattern 'PERF\[cim_query\] ms=(\d+)')
$ms=$cim | % {[int]$_.Matches[0].Groups[1].Value}
Rep ("cim_query n={0} max={1} sum={2}" -f $cim.Count, ($ms|Measure -Max).Maximum, ($ms|Measure -Sum).Sum)
$stale=@(Select-String -Path $dst -Pattern 'STALE_FORWARD|ORPHAN_TUNNEL|port still busy')
Rep ("stale/orphan n={0}" -f $stale.Count)
$stale | Select -First 6 | % { Rep ("  {0}" -f $_.Line.Substring(0,[Math]::Min(130,$_.Line.Length))) }
$infoN=@(Select-String -Path $dst -Pattern '\[INFO\]').Count
$allN=(Get-Content $dst|Measure).Count
Rep ("old_bug_sync_attempts~={0}  new_policy_INFO_syncs~={1}" -f $allN, [Math]::Ceiling($infoN/25.0))

# version running in active log
$lastVer = Select-String -Path $dst -Pattern 'session start v([0-9.]+)' | Select -Last 1
Rep ("last_session_line: {0}" -f $lastVer.Line.Substring(0,[Math]::Min(140,$lastVer.Line.Length)))

$out=Join-Path $env:TEMP 'deep-audit-report.txt'
$rep | Set-Content $out -Encoding utf8
Rep ("REPORT=$out lines=$($rep.Count)")
Remove-Item $dst,$srv -Force -EA SilentlyContinue
