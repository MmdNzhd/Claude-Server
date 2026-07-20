$ErrorActionPreference = 'Continue'
Write-Host '=== add-user SQL ==='
(Get-Content scripts\server\commands\add-user.sh)[168..180] | ForEach-Object { $_ }
Write-Host '=== add-user AK ==='
(Get-Content scripts\server\commands\add-user.sh)[255..280] | ForEach-Object { $_ }
Write-Host '=== connect elevate ==='
(Get-Content scripts\client\windows\connect.ps1)[20..45] | ForEach-Object { $_ }
Write-Host '=== admin AK lines ==='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'administrators_authorized' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== EnsureLaptopSshReady admin write ==='
Select-String -Path scripts\client\windows\connect.ps1,scripts\client\git-mode.ps1 -Pattern 'administrators_authorized_keys' -Context 0,3 | ForEach-Object { $_.ToString() }
Write-Host '=== diagnose pulls key ==='
Select-String -Path scripts\server\commands\diagnose-auth.sh -Pattern 'private|claude_laptop|IdentityFile|\.ssh/' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== install auth log modes ==='
Select-String -Path scripts\server\commands\install.sh -Pattern 'claude-auth.log|cursor-auth-refresh.log|activity.jsonl|oauth.env|claude-code' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== deploy-auth uses lib? ==='
Select-String -Path scripts\server\commands\deploy-auth.sh -Pattern 'write_env|oauth.env|environment|claude-auth-lib' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== claude-auth-sync token source ==='
Select-String -Path scripts\server\claude-auth-sync.sh -Pattern 'environment|oauth.env|TOKEN|read_env' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== pwB64 in remote wrap (cmdline leak) ==='
Select-String -Path publish\deploy-client-bundles.ps1 -Pattern 'pwB64|base64|PW=\$\(echo' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== FIX-AGENT-1 again ==='
Test-Path scripts\tmp\FIX-AGENT-1.md
Get-ChildItem scripts\tmp\FIX-AGENT*.md -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime
Write-Host '=== git tracked sepidz@Admin outside tmp ==='
git --no-pager grep -n 'sepidz@Admin' -- ':!scripts/tmp/**' ':!publish/*.local.ps1' 2>$null
if ($LASTEXITCODE -ne 0) { 'git-grep: no matches outside tmp/local' }
