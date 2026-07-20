$ErrorActionPreference='Continue'
function Show($title,$path,$pat){
  Write-Host "=== $title ==="
  if(-not (Test-Path $path)){ Write-Host "MISSING $path"; return }
  Write-Host ("lines=" + (Get-Content $path).Count)
  Select-String -Path $path -Pattern $pat | ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)) }
}
Show 'win-update' 'scripts\client\windows\connect-update.ps1' 'IdentityAgent|IdentitiesOnly|function Test-BundleChecksums|checksums|Swap-LiveDir|applied_ok|exit 1|NEW_ROOT|BakRoot'
Show 'mac-update' 'scripts\client\mac\connect-update.sh' 'IdentityAgent|checksum|_swap_dir|NEW_ROOT|applied_ok|exit 1|cp -f'
Show 'mount-load' 'scripts\server\claude-mount.sh' 'tr -d .r.|restore_try|Remove-Item \$p/\.git'
Show 'watchdog' 'scripts\server\claude-watchdog.sh' 'MOUNT_BIN.*down|first alphabetical|tr -d'
Show 'bat' 'scripts\client\windows\connect.bat' 'UPDATE_DEPTH|errorlevel'
Show 'install-golden' 'scripts\server\commands\install.sh' 'chmod 600 /etc/cursor-auth|golden/\*|auth\.json'
Show 'creds' 'publish\Get-DeployCredentials.ps1' 'throw|fallback|Admin'
Show 'bundles-pw' 'publish\deploy-client-bundles.ps1' 'Get-SepidzSudoPassword|Get-SmartSudoPassword|hardcoded|fallback|UTF8Encoding'
