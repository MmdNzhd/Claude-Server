$ErrorActionPreference='Continue'
function Show($title,$path,$pat){
  Write-Host "=== $title ==="
  if(-not (Test-Path $path)){ Write-Host "MISSING $path"; return }
  Write-Host ("lines=" + (Get-Content $path).Count)
  Select-String -Path $path -Pattern $pat | ForEach-Object {
    $line = $_.Line.Trim()
    if($line.Length -gt 110){ $line = $line.Substring(0,110) }
    "{0}: {1}" -f $_.LineNumber, $line
  }
}
Show 'mac-update' 'scripts\client\mac\connect-update.sh' 'SSH_EXTRA_OPTS|IdentityAgent|_verify_checksums|_swap_dir|NEW_ROOT|applied_ok|exit 1|_run_timed'
Show 'win-update' 'scripts\client\windows\connect-update.ps1' 'IdentityAgent|Test-BundleChecksums|Swap-LiveDir|applied_ok|exit 1'
Show 'bat' 'scripts\client\windows\connect.bat' 'UPDATE_DEPTH'
Show 'mac-connect' 'scripts\client\mac\connect.sh' 'UPDATE_DEPTH'
Show 'mount' 'scripts\server\claude-mount.sh' 'tr -d .\\r.|restore_try|PathType Leaf'
Show 'watchdog' 'scripts\server\claude-watchdog.sh' 'MOUNT_BIN.*down|first alphabetical'
Show 'automount' 'scripts\server\claude-automount.sh' 'tr -d|first alphabetical'
Show 'install' 'scripts\server\commands\install.sh' 'chmod 600 /etc/cursor-auth|oauth.env|Migrate legacy|PYMIG'
Show 'add-user' 'scripts\server\commands\add-user.sh' 'SQLSERVER_PASSWORD'
Show 'creds' 'publish\Get-DeployCredentials.ps1' 'No hardcoded|throw'
Show 'bundles' 'publish\deploy-client-bundles.ps1' 'UTF8Encoding|Get-SepidzSudoPassword|hardcoded'
Show 'gitignore' '.gitignore' 'sepidz-deploy|smart-deploy'
Show 'claude-md-sql' 'CLAUDE.md' 'SQLSERVER_PASSWORD'
