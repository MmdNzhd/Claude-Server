$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$bash = @"
set +e
PW=`$(printf '%s' '$pwB64' | base64 -d)
sudo_run() { printf '%s\n' "`$PW" | sudo -S -p '' bash -lc "`$1"; }

# Fix machineid - strip quotes
sudo_run 'GOLD=`$(tr -d \"\\\"\\r\\n \" < /etc/cursor-auth/golden/machine-id.txt); printf \"%s\" \"`$GOLD\" > /home/farzadb/.config/Cursor/machineid; printf \"%s\" \"`$GOLD\" > /home/farzadb/.cursor-server/data/machineid; chown farzadb:farzadb /home/farzadb/.config/Cursor/machineid /home/farzadb/.cursor-server/data/machineid; echo PROFILE_HEX=; xxd /home/farzadb/.config/Cursor/machineid | head -2; echo SERVER_HEX=; xxd /home/farzadb/.cursor-server/data/machineid | head -2; echo GOLDEN_HEX=; xxd /etc/cursor-auth/golden/machine-id.txt | head -2'

# Check bashrc hang
echo '=== shell env probe ==='
sudo_run 'timeout 3 su - farzadb -c \"echo SHELL_OK; echo PATH=\`$PATH\" 2>&1; echo ec=`$?'
sudo_run 'wc -l /home/farzadb/.bashrc /home/farzadb/.profile /home/farzadb/.bash_profile 2>&1; grep -nE \"sleep|claude|mount|sshfs|while|laptop\" /home/farzadb/.bashrc /home/farzadb/.profile 2>/dev/null | head -30'

# Remount projects if tunnel up
echo '=== remount ==='
sudo_run 'su - farzadb -c \"export CLAUDE_TRUSTED_TUNNEL=1; claude-mount status 2>&1 | head -40; claude-mount backend 2>&1 | tail -20; claude-mount frontend 2>&1 | tail -20; mountpoint /home/farzadb/mounts/backend; mountpoint /home/farzadb/mounts/frontend; ls /home/farzadb/mounts/backend 2>&1 | head; ls /home/farzadb/mounts/frontend 2>&1 | head\"'

echo DONE
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -o BatchMode=yes -o ConnectTimeout=45 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
