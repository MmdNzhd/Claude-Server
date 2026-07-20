$Server = 'smart@192.168.210.240'
Write-Host "Smart sudoers.d:" -ForegroundColor Cyan
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server 'ls -la /etc/sudoers.d/ 2>/dev/null; echo ---; grep -r claude /etc/sudoers.d/ 2>/dev/null; echo ---; ls -la /usr/local/share/claude-client/connect-version.txt 2>/dev/null'
Write-Host "`nSepidz sudoers.d:" -ForegroundColor Cyan
& ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.250.70 'ls -la /etc/sudoers.d/ 2>/dev/null; echo ---; grep -r claude /etc/sudoers.d/ 2>/dev/null'
