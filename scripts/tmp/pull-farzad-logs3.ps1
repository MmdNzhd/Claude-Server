$ErrorActionPreference = 'Continue'
. D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1
$pw = Get-SepidzSudoPassword
Write-Output '=== T1 ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.250.70 "hostname; cat /usr/local/share/claude-client/connect-version.txt"
Write-Output '=== T2 sudo hostname ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.250.70 "printf '%s\n' '$pw' | sudo -S -p '' hostname"
Write-Output '=== T3 logs ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.250.70 "printf '%s\n' '$pw' | sudo -S -p '' ls -lah /home/farzadb/.claude/logs/"
Write-Output '=== T4 conf ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.250.70 "printf '%s\n' '$pw' | sudo -S -p '' cat /home/farzadb/.claude-connect.conf"
Write-Output '=== T5 find ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.250.70 "printf '%s\n' '$pw' | sudo -S -p '' find /home/farzadb/.claude -name connect* -type f"
Write-Output '=== T6 latest ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=25 -o IdentityAgent=none smart@192.168.250.70 "printf '%s\n' '$pw' | sudo -S -p '' bash -lc 'L=$(ls -1t /home/farzadb/.claude/logs/connect*.log 2>/dev/null | head -1); echo LATEST=$L; ls -lah \"$L\"; wc -l \"$L\"; echo ---TAIL---; tail -n 250 \"$L\"'"
Write-Output '=== DONE ==='
