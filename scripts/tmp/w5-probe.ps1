$ErrorActionPreference='Continue'
Write-Host '=== connect-update markers ==='
$p='scripts\client\windows\connect-update.ps1'
Write-Host ("lines=" + (Get-Content $p).Count)
Select-String -Path $p -Pattern 'IdentityAgent|IdentitiesOnly|checksum|Test-Bundle|applied_ok|exit 1|SshCommonOpts' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== mount CR strip ==='
Select-String -Path 'scripts\server\claude-mount.sh' -Pattern 'tr -d|_load_global' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== automount CR ==='
Select-String -Path 'scripts\server\claude-automount.sh' -Pattern 'tr -d|TUNNEL_PORT' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== install oauth/golden ==='
Select-String -Path 'scripts\server\commands\install.sh' -Pattern 'chmod 600 /etc/cursor-auth|golden/\*|oauth\.env|migrate|strip' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== mac update IdentityAgent ==='
Select-String -Path 'scripts\client\mac\connect-update.sh' -Pattern 'IdentityAgent|checksum|exit 1' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== deploy bundles BOM ==='
Select-String -Path 'publish\deploy-client-bundles.ps1' -Pattern 'UTF8Encoding|Set-Content.*manifest|WriteAllBytes.*manifest' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== add-user SQL ==='
Select-String -Path 'scripts\server\commands\add-user.sh' -Pattern 'SQLSERVER_PASSWORD' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
