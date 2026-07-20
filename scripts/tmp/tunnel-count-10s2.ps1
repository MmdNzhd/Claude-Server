$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
$cmd='f=/home/smart/.claude/logs/connect-20260719.log; printf "start="; grep -c "session start" "$f"; printf "end="; grep -c "session end" "$f"; printf "DROP="; grep -c TUNNEL_DROP "$f"; printf "soft="; grep -c "soft_fail" "$f"; printf "SYNC="; grep -c TUNNEL_SYNC "$f"; printf "ENSURE="; grep -c ENSURE_TUNNEL "$f"; printf "ORPHAN="; grep -c ORPHAN_TUNNEL "$f"; printf "RECOV="; grep -c RECOVERY_BEGIN "$f"; printf "fall="; grep -c fallthrough_recover "$f"; printf "quit="; grep -c user_quit "$f"'
$p=Start-Process -FilePath ssh -ArgumentList ($ssh+@('claude-server-sepidz',$cmd)) -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\t10b-out.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\t10b-err.txt'
if(-not $p.WaitForExit(10000)){ try{$p.Kill()}catch{}; 'TIMEOUT' }
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\t10b-out.txt' -Raw
# farzad soft_fail / quit alternate
$t=[IO.File]::ReadAllText('D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log')
"farzad soft_fail=$([regex]::Matches($t,'soft_fail').Count) quit=$([regex]::Matches($t,'user_quit|keychar=q |DISCONNECT|disconnect project').Count) CLEAR_MOUNT=$([regex]::Matches($t,'CLEAR_MOUNT').Count)"
