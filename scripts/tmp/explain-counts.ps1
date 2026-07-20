$ErrorActionPreference='Continue'
$f='D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
$t=[IO.File]::ReadAllText($f)
function C($rx){[regex]::Matches($t,$rx).Count}
Write-Output 'FARZAD verification:'
Write-Output ("session start v = {0}" -f (C 'session start v'))
Write-Output ("session end = {0}" -f (C '======== session end'))
Write-Output ("TUNNEL_DROP = {0}" -f (C 'TUNNEL_DROP'))
Write-Output ("soft_fail = {0}" -f (C 'soft_fail'))
Write-Output ("TUNNEL_SYNC = {0}" -f (C 'TUNNEL_SYNC'))
Write-Output ("TUNNEL_SYNC TRACE-ish = {0}" -f (C 'TUNNEL_SYNC.*(TRACE|ok=1|bg_alive)'))
Write-Output ("ENSURE_TUNNEL = {0}" -f (C 'ENSURE_TUNNEL'))
Write-Output ("ORPHAN_TUNNEL = {0}" -f (C 'ORPHAN_TUNNEL'))
Write-Output ("RECOVERY_BEGIN = {0}" -f (C 'RECOVERY_BEGIN'))
Write-Output ("fallthrough = {0}" -f (C 'fallthrough_recover'))
Write-Output ("reason=user_quit = {0}" -f (C 'reason=user_quit'))
Write-Output ("DISCONNECT = {0}" -f (C 'SESSION: disconnect'))
Write-Output ("keychar quit-ish = {0}" -f (C 'keychar=q|keychar=ض'))
# sample ENSURE
Write-Output 'ENSURE samples:'
[regex]::Matches($t,'ENSURE_TUNNEL[^\r\n]{0,80}') | Select-Object -First 8 | ForEach-Object { $_.Value }
Write-Output 'ORPHAN samples:'
[regex]::Matches($t,'ORPHAN_TUNNEL[^\r\n]{0,80}') | Select-Object -First 5 | ForEach-Object { $_.Value }
Write-Output 'TUNNEL_SYNC sample kinds:'
$sync=[regex]::Matches($t,'GITMODE: TUNNEL_SYNC[^\r\n]{0,100}|TUNNEL_SYNC[^\r\n]{0,100}') | ForEach-Object { $_.Value }
$sync | ForEach-Object { if($_ -match 'reason=([^\s]+)'){$Matches[1]} elseif($_ -match 'ok=(\d)'){"ok=$($Matches[1])"} else {'other'} } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {"{0,4} {1}" -f $_.Count,$_.Name}

# SMART via 10s ssh - single word patterns only + session via E
$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
$cmd='f=/home/smart/.claude/logs/connect-20260719.log; echo start_v=$(grep -cE "session start v" "$f"); echo end=$(grep -cE "session end" "$f"); echo DROP=$(grep -c TUNNEL_DROP "$f"); echo soft=$(grep -c soft_fail "$f"); echo SYNC=$(grep -c TUNNEL_SYNC "$f"); echo ENSURE=$(grep -c ENSURE_TUNNEL "$f"); echo ORPHAN=$(grep -c ORPHAN_TUNNEL "$f"); echo RECOV=$(grep -c RECOVERY_BEGIN "$f"); echo uniq_start=$(grep -E "session start v" "$f" | sort -u | wc -l)'
$p=Start-Process ssh -ArgumentList ($ssh+@('claude-server-sepidz',$cmd)) -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\ex-out.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\ex-err.txt'
[void]$p.WaitForExit(10000)
Write-Output 'SMART verify:'
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\ex-out.txt' -Raw
