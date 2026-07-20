$v = ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 'tr -d "\r\n" </usr/local/share/claude-client/connect-version.txt'
Write-Host "Smart version: $v"
$v2 = ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 'tr -d "\r\n" </usr/local/share/claude-client/connect-version.txt'
Write-Host "Sepidz version: $v2"
