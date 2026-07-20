. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
Select-String -Path 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1' -Pattern 'function Get-Smart|SmartSsh|210.240' | ForEach-Object { $_.Line.Trim() }
$u = if($env:SMART_SSH_USER){$env:SMART_SSH_USER} else {
  $v = $null
  try { $v = Read-LocalDeployValue -FileName 'smart-deploy.local.ps1' -Name 'SmartSshUser' } catch {}
  if($v){$v} else {'smart'}
}
Write-Output "trying user=$u"
& ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -o IdentityAgent=none "${u}@192.168.210.240" "hostname; tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo" 2>&1 | ForEach-Object { "$_" }
Write-Output "exit=$LASTEXITCODE"
# also try from deploy script targets
Select-String -Path 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1','D:\Smart\Claude-Code-Server\publish\deploy-smart-bundle.ps1' -Pattern '210.240|SmartSsh|Get-Smart' | Select-Object -First 15 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
