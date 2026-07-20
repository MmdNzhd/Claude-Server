ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.250.70 'rm -f $HOME/.claude/logs/.connect-*.tmp; ls -la $HOME/.claude/logs; echo VER; cat /usr/local/share/claude-client/connect-version.txt'
Write-Host '---'
ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'echo SMART_VER; cat /usr/local/share/claude-client/connect-version.txt'
