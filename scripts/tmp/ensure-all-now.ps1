$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$sp = Get-SmartSudoPassword
$zp = Get-SepidzSudoPassword
Write-Output ("smart_pw_len={0}" -f $(if($sp){$sp.Length}else{0}))
Write-Output ("sepidz_pw_len={0}" -f $(if($zp){$zp.Length}else{0}))
Write-Output ("smart_local_exists={0}" -f (Test-Path 'D:\Smart\Claude-Code-Server\publish\smart-deploy.local.ps1'))
Write-Output ("pack_ver={0}" -f (Get-Content "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt" -Raw).Trim())
