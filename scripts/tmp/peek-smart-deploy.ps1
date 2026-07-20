$ErrorActionPreference='Stop'
$p='D:\Smart\Claude-Code-Server\publish\publish.ps1'
Select-String -Path $p -Pattern 'Deploying Smart|deploy-client-bundles|SkipServerDeploy|SmartOnly' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '--- Invoke-RemoteBundleInstall full ---'
$d='D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
$lines=Get-Content $d
161..230 | ForEach-Object { "{0,4}|{1}" -f $_, $lines[$_-1] }
Write-Output '--- end of deploy script ---'
240..([Math]::Min(280,$lines.Count)) | ForEach-Object { "{0,4}|{1}" -f $_, $lines[$_-1] }
