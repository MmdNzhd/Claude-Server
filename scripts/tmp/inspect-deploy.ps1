Write-Output '=== Get-DeployCredentials.ps1 ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1' -Pattern 'function |param\(|Password|ssh' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== deploy-client-bundles auth ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' -Pattern 'password|Credential|sshpass|plink|Ssh|Identity|BatchMode' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
