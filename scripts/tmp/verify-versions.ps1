Write-Output '=== Sepidz remote version ==='
& ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -o IdentityAgent=none sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo; tr -d '\r\n' < /usr/local/share/claude-client/windows/connect-version.txt 2>/dev/null; echo; hostname" 2>&1
Write-Output '=== Smart remote version ==='
& ssh -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -o IdentityAgent=none smart@192.168.210.240 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo; hostname" 2>&1
Write-Output "smart_ssh_exit=$LASTEXITCODE"
# Try alternate user if needed
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$smartTarget = if(Get-Command Get-SmartServerTarget -EA SilentlyContinue){ Get-SmartServerTarget } else { 'smart@192.168.210.240' }
Write-Output "smartTarget=$smartTarget"
# from smart-deploy.local
$sf='D:\Smart\Claude-Code-Server\publish\smart-deploy.local.ps1'
if(Test-Path $sf){ Select-String -Path $sf -Pattern 'SshUser|Host|Target' | ForEach-Object { ($_.Line -replace '=.*','=<redacted>').Trim() } }
