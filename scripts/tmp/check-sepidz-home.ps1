$Server = 'sepidz@192.168.250.70'
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server 'ls -la ~/claude-client-bundle-deploy/ 2>&1; ls -la /usr/local/share/claude-client/ 2>&1'
