$ErrorActionPreference='Continue'
function Rep($s){ Write-Host $s }

# Deployed windows bits only
$py = @'
from pathlib import Path
import hashlib
p=Path("/usr/local/share/claude-client/connect-ui.ps1")
t=p.read_text(errors="replace")
print("ver", Path("/usr/local/share/claude-client/connect-version.txt").read_text().strip())
print("sha", hashlib.sha256(t.encode()).hexdigest()[:16])
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
print("ls_client")
import os
for n in sorted(os.listdir("/usr/local/share/claude-client"))[:40]:
    print(" ", n)
'@
Set-Content (Join-Path $env:TEMP 'dr.py') $py -Encoding ascii
scp -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no -q (Join-Path $env:TEMP 'dr.py') smart@192.168.250.70:/tmp/dr.py
ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 'python3 /tmp/dr.py; rm -f /tmp/dr.py' | ForEach-Object { Rep "DEPLOY $_" }
$smart=(ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
Rep "Smart=$smart"
$src=(Get-FileHash scripts\client\connect-ui.ps1 -Algorithm SHA256).Hash.Substring(0,16)
Rep "src_sha=$src"

# Mac source policy detail
Rep '======== MAC connect_log policy ========'
Select-String -Path scripts\client\connect-ui.sh -Pattern 'connect_log\(|level|SYNC|TRACE|DEBUG|ge ' |
  Select-Object -First 50 | ForEach-Object { Rep ("L{0}: {1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length))) }

# Local vs server
Rep '======== LOG DIFF ========'
$local=Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst=Join-Path $env:TEMP 'deep-local.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite')
try{$o=[IO.File]::Create($dst);try{$fs.CopyTo($o)}finally{$o.Close()}}finally{$fs.Close()}
$srv=Join-Path $env:TEMP 'deep-server.log'
scp -o BatchMode=yes -o ConnectTimeout=90 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srv
Rep ("sizes local={0} server={1} gap={2}" -f (Get-Item $dst).Length,(Get-Item $srv).Length,((Get-Item $dst).Length-(Get-Item $srv).Length))

$markers=@('BOOTSTRAP: connect.bat start','UPDATE:','======== session start','DECISION: project_select','STEP end: Server setup','STEP end: Loading projects','SESSION_LOOP begin','STEP end: Mounting files','LAUNCH begin','Connection dropped','LOG_SYNC_FAIL','EXIT_WAIT','VERIFY_PROBE','DEEPSTRESS','False')
foreach($m in $markers){
  $a=@(Select-String -Path $dst -SimpleMatch $m).Count
  $b=@(Select-String -Path $srv -SimpleMatch $m).Count
  $flag= if($a -eq $b){'EQ'} elseif($b -eq 0 -and $a -gt 0){'MISS'} elseif($a -gt $b){'BEHIND'} else {'EXTRA'}
  Rep ("[{0,-6}] L={1,5} S={2,5}  {3}" -f $flag,$a,$b,$m)
}

Rep 'sessions:'
Select-String -Path $dst -Pattern 'session start v([0-9.]+).*session=([a-f0-9]+)' | % {
  Rep ("LOCAL  sess={0} ver={1} ts={2}" -f $_.Matches[0].Groups[2].Value,$_.Matches[0].Groups[1].Value,$_.Line.Substring(1,23))
}
Select-String -Path $srv -Pattern 'session start v([0-9.]+).*session=([a-f0-9]+)' | % {
  Rep ("SERVER sess={0} ver={1} ts={2}" -f $_.Matches[0].Groups[2].Value,$_.Matches[0].Groups[1].Value,$_.Line.Substring(1,23))
}

Rep 'STEP ends:'
Select-String -Path $dst -Pattern 'STEP end:' | Select -First 18 | % { Rep $_.Line.Substring(0,[Math]::Min(145,$_.Line.Length)) }

Rep 'levels L:'
Select-String -Path $dst -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | % Matches | % {$_.Groups[1].Value} | Group | Sort Count -Desc | % { Rep ("  {0}={1}" -f $_.Name,$_.Count) }
Rep 'levels S:'
Select-String -Path $srv -Pattern '\[(INFO|WARN|ERROR|DEBUG|TRACE)\]' -AllMatches | % Matches | % {$_.Groups[1].Value} | Group | Sort Count -Desc | % { Rep ("  {0}={1}" -f $_.Name,$_.Count) }

$wm=$local+'.sync-offset'
if(Test-Path $wm){Rep ("watermark={0} size={1}" -f (Get-Content $wm -Raw).Trim(),(Get-Item $local).Length)} else {Rep 'watermark=MISSING'}

# prefix
function StripBom([byte[]]$b){ if($b.Length-ge3 -and $b[0]-eq0xEF -and $b[1]-eq0xBB -and $b[2]-eq0xBF){ $n=New-Object byte[] ($b.Length-3);[Array]::Copy($b,3,$n,0,$n.Length);return $n}; return $b}
$lb=StripBom ([IO.File]::ReadAllBytes($dst)); $sb=StripBom ([IO.File]::ReadAllBytes($srv))
$same=$true; $lim=[Math]::Min(65536,$sb.Length,$lb.Length)
for($i=0;$i -lt $lim;$i++){ if($lb[$i]-ne $sb[$i]){ $same=$false; Rep "first_diff@$i"; break } }
Rep "prefix64k=$same"

Rep '======== LIVE SYNC ========'
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
$leaks=0
1..3 | % { $script:ConnectLogSyncOffset=0; if((Sync-ConnectLogToServer|Out-String).Trim()){ $leaks++ } }
$g=ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log; grep -c TRACE_ONLY ~/.claude/logs/connect-20260719.log; grep -F '$tag WARN_FLUSH' ~/.claude/logs/connect-20260719.log | wc -l"
Rep ("LastOk={0} leaks={1} server_counts={2}" -f $script:LastConnectLogSyncOk,$leaks,($g -replace "`n",','))
Remove-Item $tfile,($tfile+'.sync-offset') -Force -EA SilentlyContinue

Rep '======== PERF ========'
$cim=@(Select-String -Path $dst -Pattern 'PERF\[cim_query\] ms=(\d+)')
$ms=@($cim | % {[int]$_.Matches[0].Groups[1].Value})
if($ms.Count){ Rep ("cim n={0} max={1} sum={2}" -f $cim.Count,($ms|Measure -Max).Maximum,($ms|Measure -Sum).Sum) }
$stale=@(Select-String -Path $dst -Pattern 'STALE_FORWARD|ORPHAN_TUNNEL|port still busy')
Rep ("stale_n={0}" -f $stale.Count)
$stale | Select -First 5 | % { Rep $_.Line.Substring(0,[Math]::Min(130,$_.Line.Length)) }
$infoN=@(Select-String -Path $dst -Pattern '\[INFO\]').Count
$allN=(Get-Content $dst|Measure).Count
Rep ("old_sync~={0} new_info_sync~={1}" -f $allN,[Math]::Ceiling($infoN/25.0))
$last=Select-String -Path $dst -Pattern 'session start v([0-9.]+)' | Select -Last 1
Rep ("last_session={0}" -f $last.Line.Substring(0,[Math]::Min(140,$last.Line.Length)))
Remove-Item $dst,$srv -Force -EA SilentlyContinue
Rep DONE
