$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$smart = Get-SmartSudoPassword
$sepid = Get-SepidzSudoPassword
$st = Get-SepidzServerTarget
Write-Output ("smart_sudo_len={0}" -f $(if($smart){$smart.Length}else{0}))
Write-Output ("sepidz_sudo_len={0}" -f $(if($sepid){$sepid.Length}else{0}))
Write-Output ("sepidz_target={0}" -f $st)
