$ErrorActionPreference = 'Continue'
. D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1
$pw = Get-SepidzSudoPassword
Write-Output "pw_len=$($pw.Length)"
$bash = @"
printf '%s\n' '$pw' | sudo -S -p '' bash -lc 'hostname; cat /usr/local/share/claude-client/connect-version.txt; echo ---LOGS---; ls -lah /home/farzadb/.claude/logs/ | tail -40; echo ---CONF---; cat /home/farzadb/.claude-connect.conf; echo ---FIND---; find /home/farzadb/.claude -name "connect*" -type f | head -30; L=`$(ls -1t /home/farzadb/.claude/logs/connect*.log 2>/dev/null | head -1); echo LATEST=`$L; if [ -n "`$L" ]; then wc -l "`$L"; echo ---TAIL---; tail -n 150 "`$L"; fi'
"@
$bash | ssh -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none smart@192.168.250.70 "bash -s"
