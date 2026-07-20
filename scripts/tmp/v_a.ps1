Write-Host 'A1 versions'
ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o ControlMaster=no smart@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt'
ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o ControlMaster=no smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt'
Write-Host 'A1 done'
