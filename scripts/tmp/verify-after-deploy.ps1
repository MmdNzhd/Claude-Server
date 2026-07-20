Write-Output '=== SEPIDZ ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt; echo; grep -nF 'base64 -d | bash' /usr/local/share/claude-client/git-mode.ps1 | head -3; grep -nF 'reason=user_quit' /usr/local/share/claude-client/connect.ps1 | head -3; grep -nF 'RECOVERY_SKIP_CLEAR_MOUNT' /usr/local/share/claude-client/connect.ps1 | head -2; grep -nF 'PUSH_CONF begin' /usr/local/share/claude-client/git-mode.ps1 | head -2"
Write-Output '=== SMART ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.210.240 "hostname; cat /usr/local/share/claude-client/connect-version.txt"
Write-Output '=== LOCAL VERSIONS ==='
Get-Content D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt
Get-Content D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt
