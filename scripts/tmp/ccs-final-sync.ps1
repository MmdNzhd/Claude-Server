$ErrorActionPreference='Stop'
$repoBat = (Resolve-Path 'scripts\client\windows\connect.bat').Path
$repoUpd = (Resolve-Path 'scripts\client\windows\connect-update.ps1').Path
$targets = @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows')
)
foreach ($t in $targets) {
  Copy-Item -Force $repoBat (Join-Path $t 'connect.bat')
  Copy-Item -Force $repoUpd (Join-Path $t 'connect-update.ps1')
  $heal = (Get-Content (Join-Path $t 'connect.bat') -Raw) -match 'HEAL_UPDATE_BOOTSTRAP'
  $bug = (Get-Content (Join-Path $t 'connect-update.ps1') -Raw) -match 'if \(\$script:UpdateEndpointTarget\)'
  Write-Host ("{0} heal={1} update_bug={2}" -f $t, $heal, $bug)
}
# Also copy healed bat into publish package for next zip users
Write-Host 'DONE'
