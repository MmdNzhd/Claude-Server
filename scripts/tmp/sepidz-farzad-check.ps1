$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$bash = @"
set +e
PW=`$(printf '%s' '$pwB64' | base64 -d)
sudo_run() { printf '%s\n' "`$PW" | sudo -S -p '' bash -lc "`$1"; }
echo '=== find farzad users ==='
sudo_run 'getent passwd | grep -i farzad; getent passwd | grep -i farz; ls /home | grep -i farz'
echo '=== bundle ver ==='
sudo_run 'cat /usr/local/share/claude-client/connect-version.txt'
echo DONE
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
# also smart
Write-Host '==== SMART ===='
& ssh -o BatchMode=yes -o ConnectTimeout=15 smart@192.168.210.240 "getent passwd | grep -i farz; ls /home | grep -i farz; cat /usr/local/share/claude-client/connect-version.txt"
