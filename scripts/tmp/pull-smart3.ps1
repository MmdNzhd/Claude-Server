$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
$cmd=@'
echo VER=$(cat /usr/local/share/claude-client/connect-version.txt)
ls -la /home/smart/.claude/logs/ | tail -10
for d in 20260720 20260719 20260718; do
  f=/home/smart/.claude/logs/connect-$d.log
  if [ -f "$f" ]; then
    echo "==== smart $d $(wc -c <"$f") ===="
    grep -E "ERROR|Unexpected|AA616|AUTH_|session start v|Disconnect|DISCONNECT|soft_fail|Connection|TIMED|Agent Execution" "$f" | tail -50
  fi
done
# other users on smart if any
ls /home 2>/dev/null
'@
$p=Start-Process ssh -ArgumentList ($ssh+@('smart@192.168.210.240',$cmd)) -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\sm3.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\sm3.err'
[void]$p.WaitForExit(15000)
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\sm3.txt' -Raw
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\sm3.err' -EA SilentlyContinue
