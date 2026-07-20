$ErrorActionPreference='Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$sp = Get-SmartSudoPassword
Write-Output ("smart_local={0}" -f (Test-Path 'D:\Smart\Claude-Code-Server\publish\smart-deploy.local.ps1'))
Write-Output ("smart_pw_len={0}" -f $(if($sp){$sp.Length}else{0}))
Write-Output ("env_len={0}" -f $(if($env:SMART_SUDO_PASSWORD){$env:SMART_SUDO_PASSWORD.Length}else{0}))
# list any new local files
Get-ChildItem 'D:\Smart\Claude-Code-Server\publish\*.local.ps1' -EA SilentlyContinue | ForEach-Object { $_.Name }
