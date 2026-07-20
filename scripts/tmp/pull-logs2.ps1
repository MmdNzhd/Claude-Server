$ErrorActionPreference='Continue'
$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')

# Is Remove-CursorAuthTempDir used everywhere?
Write-Output '=== uses of Remove-Item.*tmp / Remove-CursorAuthTempDir ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1' -Pattern 'Remove-Item.*\$tmp|Remove-CursorAuthTempDir|Get-CursorAuthTempRoot|8\.3' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }

# Sepidz by IP
$cmd=@'
echo HOST=$(hostname) VER=$(cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null)
# try readable
for u in farzadb alit smart; do
  echo "-- $u --"
  ls -la /home/$u/.claude/logs/ 2>/dev/null | tail -5 || echo no_logs_dir
done
# sudo without password?
sudo -n true 2>/dev/null && echo SUDO_OK || echo NO_SUDO
if sudo -n true 2>/dev/null; then
  for u in farzadb alit; do
    for d in 20260720 20260719; do
      f=/home/$u/.claude/logs/connect-$d.log
      if [ -f "$f" ]; then
        echo "==== $u $d $(wc -c <"$f") ===="
        grep -E "ERROR|Unexpected|AA616|Remove-Item|AUTH_SYNC|session start v|Disconnecting|DISCONNECT|already ok|Connection" "$f" | tail -35
      fi
    done
  done
fi
'@
$p=Start-Process ssh -ArgumentList ($ssh+@('sepidz@192.168.250.70',$cmd)) -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\sz2.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\sz2.err'
[void]$p.WaitForExit(15000)
Write-Output '=== SEPIDZ IP ==='
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\sz2.txt' -Raw
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\sz2.err' -EA SilentlyContinue | Select-Object -First 8

# Smart errors today
$cmd2='for d in 20260720 20260719; do f=/home/smart/.claude/logs/connect-$d.log; if [ -f "$f" ]; then echo ====smart $d====; grep -E "ERROR|Unexpected|AA616|AUTH_|session start v|Connection Error|TIMED" "$f" | tail -40; fi; done; cat /usr/local/share/claude-client/connect-version.txt'
$p2=Start-Process ssh -ArgumentList ($ssh+@('smart@192.168.210.240',$cmd2)) -NoNewWindow -PassThru -RedirectStandardOutput 'D:\Smart\Claude-Code-Server\scripts\tmp\sm2.txt' -RedirectStandardError 'D:\Smart\Claude-Code-Server\scripts\tmp\sm2.err'
[void]$p2.WaitForExit(12000)
Write-Output '=== SMART ==='
Get-Content 'D:\Smart\Claude-Code-Server\scripts\tmp\sm2.txt' -Raw
