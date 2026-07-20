$ErrorActionPreference='Continue'
$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-o','ServerAliveInterval=3','-o','ServerAliveCountMax=2')
# FARZAD already known locally - recount quick
$f='D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
$t=[IO.File]::ReadAllText($f)
function C($rx){[regex]::Matches($t,$rx).Count}
Write-Output 'FARZAD day=20260719'
Write-Output ("session_start={0} session_end={1} TUNNEL_DROP={2} soft_fail={3} TUNNEL_SYNC={4} ENSURE={5} ORPHAN={6} recovery={7} user_quit_reason={8}" -f (C 'session start'),(C 'session end'),(C 'TUNNEL_DROP'),(C 'TUNNEL_SYNC soft_fail'),(C 'TUNNEL_SYNC'),(C 'ENSURE_TUNNEL'),(C 'ORPHAN_TUNNEL'),(C 'RECOVERY_BEGIN|fallthrough_recover'),(C 'reason=user_quit'))

# SMART remote - one short ssh, kill after 10s
$cmd='f=/home/smart/.claude/logs/connect-20260719.log; echo bytes=$(wc -c <"$f"); echo start=$(grep -c "session start" "$f"); echo end=$(grep -c "session end" "$f"); echo DROP=$(grep -c TUNNEL_DROP "$f"); echo soft=$(grep -c "TUNNEL_SYNC soft_fail" "$f"); echo SYNC=$(grep -c TUNNEL_SYNC "$f"); echo ENSURE=$(grep -c ENSURE_TUNNEL "$f"); echo ORPHAN=$(grep -c ORPHAN_TUNNEL "$f"); echo RECOV=$(grep -cE "RECOVERY_BEGIN|fallthrough_recover" "$f"); echo quit=$(grep -c user_quit "$f"); grep TUNNEL_DROP "$f" 2>/dev/null | sed -n "s/.*reason=/reason=/p" | sort | uniq -c | sort -rn | head -10'
$p=Start-Process -FilePath ssh -ArgumentList ($ssh+@('claude-server-sepidz',$cmd)) -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\t10-out.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\t10-err.txt'
if(-not $p.WaitForExit(10000)){ try{$p.Kill()}catch{}; Write-Output 'SMART ssh TIMEOUT 10s' }
Write-Output 'SMART:'
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\t10-out.txt' -EA SilentlyContinue
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\t10-err.txt' -EA SilentlyContinue | Select-Object -First 5
