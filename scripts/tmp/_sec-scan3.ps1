$ErrorActionPreference = 'Continue'
Write-Host '=== from= restriction on admin AK ==='
Select-String -Path scripts\client\windows\connect.ps1,scripts\client\users\designer\connect.ps1,scripts\client\git-mode.ps1 -Pattern 'from=|administrators_authorized|Add-Content|Set-Content' |
  Where-Object { $_.Line -match 'from=|adminFile|adminAk|authorized_keys|PubB|claude_laptop' } |
  Select-Object -First 40 |
  ForEach-Object { '{0}:{1}:{2}' -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== key install function excerpt ==='
$lines = Get-Content scripts\client\windows\connect.ps1
for ($i=230; $i -le 300; $i++) { '{0}:{1}' -f ($i+1), $lines[$i] }

Write-Host '=== deploy-client-bundle AK merge gone? ==='
Select-String -Path scripts\server\commands\deploy-client-bundle.sh -Pattern 'sepidz|authorized_keys|_sync_sepidz' |
  ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Host '=== settings.json perms add-user ==='
Select-String -Path scripts\server\commands\add-user.sh -Pattern 'chmod|chown|settings.json' |
  ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Host '=== CLAUDE.md SQL password ==='
Select-String -Path CLAUDE.md -Pattern 'Mohammad123|SQLSERVER_PASSWORD|CHANGE_ME' |
  ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Host '=== install.sh OAuth instructions ==='
(Get-Content scripts\server\commands\install.sh)[510..525]

Write-Host '=== ServerBundleFiles still packaged? ==='
(Get-Content publish\deploy-client-bundles.ps1)[49..60]

Write-Host '=== gitignore scripts/tmp? ==='
Select-String -Path .gitignore -Pattern 'scripts/tmp|tmp/' | ForEach-Object { $_.Line }
