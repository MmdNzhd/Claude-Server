ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 @'
echo VER=$(cat /usr/local/share/claude-client/connect-version.txt)
grep -n FileShare /usr/local/share/claude-client/connect-ui.ps1 | head
grep -n "Level -eq .TRACE" /usr/local/share/claude-client/connect-ui.ps1 | head
grep -n "ge 25" /usr/local/share/claude-client/connect-ui.ps1 | head
grep -n "TRACE" /usr/local/share/claude-client/mac/connect-ui.sh | head -5
'@
