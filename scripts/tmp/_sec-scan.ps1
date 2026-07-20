$ErrorActionPreference = 'Continue'
Write-Host '=== sepidz@Admin in tracked-ish paths (exclude .local) ==='
Get-ChildItem -Recurse -Include *.ps1,*.sh,*.py,*.md,*.json -File |
  Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.Name -notmatch '\.local\.ps1$' } |
  Select-String -Pattern 'sepidz@Admin' -SimpleMatch -ErrorAction SilentlyContinue |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Path.Replace((Get-Location).Path+'\',''), $_.LineNumber, $_.Line.Trim() }

Write-Host '=== SQLSERVER_PASSWORD ==='
Select-String -Path scripts\server\commands\add-user.sh,CLAUDE.md -Pattern 'SQLSERVER_PASSWORD|Mohammad123' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== AK merge sepidz ==='
Select-String -Path scripts\server\commands\add-user.sh,scripts\server\commands\deploy-client-bundle.sh -Pattern 'sepidz.*authorized|_sync_sepidz|update keys' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== NOPASSWD sudoers ==='
Get-Content scripts\server\sudoers.d\claude-client-deploy

Write-Host '=== OAuth environment chmod ==='
Select-String -Path scripts\server\claude-auth-lib.py,scripts\server\commands\update-server.sh,scripts\server\commands\deploy-auth.sh,scripts\server\commands\install.sh -Pattern 'environment|chmod|profile.d/claude' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== cursor golden chmod ==='
Select-String -Path scripts\server\cursor-auth-export.sh,scripts\server\commands\import-cursor-golden-laptop.sh,scripts\server\commands\install.sh,scripts\server\cursor-auth-lib.py -Pattern 'chmod|644|640|600|750|700' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== connect Always elevate ==='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'Always run elevated|AdminFix|RunAs|Verb RunAs' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== bundle world readable / ServerBundleFiles ==='
Select-String -Path publish\deploy-client-bundles.ps1,scripts\server\commands\deploy-client-bundle.sh,scripts\server\commands\install-client-bundle.sh -Pattern 'ServerBundleFiles|chmod 755|world-readable|BUNDLE_ROOT|claude-client' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== diagnose private key / sudo echo ==='
Select-String -Path scripts\server\commands\diagnose-auth.sh,scripts\server\claude-auth-lib.py,scripts\server\sudo-from-laptop.sh -Pattern 'private|id_ed25519|fingerprint|/var/log|sudo -S|echo.*PW' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '=== FIX-AGENT-1 ==='
if (Test-Path scripts\tmp\FIX-AGENT-1.md) { 'PRESENT'; Get-Content scripts\tmp\FIX-AGENT-1.md -TotalCount 80 } else { 'ABSENT' }

Write-Host '=== gitignore local deploy ==='
Select-String -Path .gitignore -Pattern 'deploy.local|sepidz-deploy|smart-deploy' |
  ForEach-Object { $_.Line }
