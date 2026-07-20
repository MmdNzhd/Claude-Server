$ErrorActionPreference='Continue'
Write-Output '=== local files ==='
Get-ChildItem 'D:\Smart\Claude-Code-Server\publish\*deploy*.ps1' | ForEach-Object { $_.Name }
Write-Output '=== smart ssh sudo -n ==='
ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "sudo -n true && echo SMART_NOPASSWD_OK || echo SMART_NEEDS_PASSWORD"
Write-Output '=== sepidz ssh sudo -n ==='
ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "sudo -n true && echo SEPIDZ_NOPASSWD_OK || echo SEPIDZ_NEEDS_PASSWORD"
Write-Output '=== deploy-smart-bundle.ps1 ==='
Get-Content 'D:\Smart\Claude-Code-Server\publish\deploy-smart-bundle.ps1' -TotalCount 40
