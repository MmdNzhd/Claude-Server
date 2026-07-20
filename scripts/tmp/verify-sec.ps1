Set-Location 'D:\Smart\Claude-Code-Server'
$u=[IO.File]::ReadAllText('scripts\server\commands\update-server.sh')
$e=[IO.File]::ReadAllText('scripts\server\cursor-auth-export.sh')
$b=[IO.File]::ReadAllText('scripts\server\commands\install-client-bundle.sh')
Write-Output '--- update-server oauth/env lines ---'
$u -split "`n" | Select-String 'environment|NEW_TOKEN|oauth\.env|chmod' | ForEach-Object { $_.Line.Trim() }
Write-Output ('match_NEW_TOKEN_env_same_line=' + ($u -match 'CLAUDE_CODE_OAUTH_TOKEN=\$NEW_TOKEN.*environment'))
Write-Output ('match_NEW_TOKEN_any=' + ($u -match 'CLAUDE_CODE_OAUTH_TOKEN=\$NEW_TOKEN'))
Write-Output '--- export chmod ---'
$e -split "`n" | Select-String 'chmod|golden|auth.json' | ForEach-Object { $_.Line.Trim() }
Write-Output ('match_chmod644_golden=' + ($e -match 'chmod\s+644\s+/etc/cursor-auth/golden'))
Write-Output '--- bundle sepidz ---'
Write-Output ('has_sync=' + ($b -match '_sync_sepidz_update_keys'))
Write-Output ('has_home_loop=' + ($b -match 'for d in /home/\*'))
$b -split "`n" | Select-String 'sepidz|authorized|home/\*|NOPASSWD|_sync' | ForEach-Object { $_.Line.Trim() }
