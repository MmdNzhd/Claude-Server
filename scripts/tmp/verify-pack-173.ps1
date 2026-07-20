$ErrorActionPreference='Stop'
$expect='20260717.3'
foreach($pack in @(
  "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows",
  "$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows"
)){
  $v=(Get-Content "$pack\connect-version.txt" -Raw).Trim()
  $el=Get-Content "$pack\editor-launch.ps1" -Raw
  $diag=Get-Content "$pack\connect-diagnostic.ps1" -Raw
  $auth=Get-Content "$pack\cursor-auth-laptop.ps1" -Raw
  Write-Output ("PACK {0}" -f $pack)
  Write-Output ("  ver={0} ok={1}" -f $v, ($v -eq $expect))
  Write-Output ("  scan_all_users={0}" -f ($el -match 'Default User'))
  Write-Output ("  auth_temp={0}" -f ($auth -match 'Get-CursorAuthTempRoot'))
  Write-Output ("  diag_msg={0}" -f ($diag -match 'not found for this Windows user'))
  Write-Output ("  tunnel_fix={0}" -f ($el -match 'Test-TunnelBannerIsWindows' -eq $false)) # in git-mode
  $gm=Get-Content (Join-Path $pack 'git-mode.ps1') -Raw
  Write-Output ("  tunnel_derive={0}" -f ($gm -match 'Test-TunnelBannerIsWindows -Banner \$banner'))
}
# Smoke Ensure-EditorOnPath finds Smart's Cursor
. "$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows\editor-launch.ps1"
$script:LaptopUser='Smart'
$cli=Ensure-EditorOnPath 'cursor'
Write-Output ("SMOKE Ensure-EditorOnPath => {0}" -f $cli)
$exe=Get-EditorNativeExe 'cursor'
Write-Output ("SMOKE Get-EditorNativeExe => {0}" -f $exe)
