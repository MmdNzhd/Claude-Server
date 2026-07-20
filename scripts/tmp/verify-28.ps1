Write-Output '=== SEPIDZ ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt; grep -n useVk /usr/local/share/claude-client/connect.ps1 | head -5; grep -n 'base64 -d' /usr/local/share/claude-client/git-mode.ps1 | head -2"
Write-Output '=== SMART ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "hostname; cat /usr/local/share/claude-client/connect-version.txt"
