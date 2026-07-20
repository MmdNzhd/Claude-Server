$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$server = Get-SepidzServerTarget
$pw = Get-SepidzSudoPassword
Write-Host "target=$server pw_len=$($pw.Length)"
# quick ssh
& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "echo SSH_OK; id"
Write-Host "ssh_exit=$LASTEXITCODE"
# sudo -S -v like deploy script
$prev = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
$pw | & ssh -o BatchMode=yes -o ConnectTimeout=15 $server "sudo -S -v >/dev/null 2>&1 && echo SUDO_OK || echo SUDO_FAIL"
Write-Host "sudo_probe_exit=$LASTEXITCODE"
$ErrorActionPreference = $prev
# current bundle ver
& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING"
