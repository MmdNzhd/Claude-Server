$ErrorActionPreference='Stop'
$expect='20260717.3'
Write-Output "EXPECT=$expect"
Write-Output "TIME=$(Get-Date -Format o)"
$repo='D:\Smart\Claude-Code-Server'
Write-Output ("REPO_VER={0}" -f (Get-Content "$repo\scripts\client\windows\connect-version.txt" -Raw).Trim())

$smartPack="$env:USERPROFILE\Desktop\claude-publish\claude-code-client-20260717\windows"
$sepidPack="$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows"
foreach($pair in @(@('PACK_SMART',$smartPack),@('PACK_SEPIDZ',$sepidPack))){
  $n=$pair[0]; $p=$pair[1]
  $v=(Get-Content "$p\connect-version.txt" -Raw).Trim()
  $el=Get-Content "$p\editor-launch.ps1" -Raw
  $auth=Get-Content "$p\cursor-auth-laptop.ps1" -Raw
  $gm=Get-Content "$p\git-mode.ps1" -Raw
  $diag=Get-Content "$p\connect-diagnostic.ps1" -Raw
  Write-Output ("{0}_VER={1}" -f $n,$v)
  Write-Output ("{0}_CURSOR_SCAN={1}" -f $n, [int]($el -match 'Default User'))
  Write-Output ("{0}_AUTH_TEMP={1}" -f $n, [int]($auth -match 'Get-CursorAuthTempRoot'))
  Write-Output ("{0}_TUNNEL={1}" -f $n, [int]($gm -match 'Test-TunnelBannerIsWindows -Banner \$banner'))
  Write-Output ("{0}_KILLFIX={1}" -f $n, [int](($el -match 'preserve_open_windows') -and ($el -notmatch 'pre_launch_agent_or_new_window')))
  Write-Output ("{0}_DIAG={1}" -f $n, [int]($diag -match 'not found for this Windows user'))
  Write-Output ("{0}_OK={1}" -f $n, [int](($v -eq $expect) -and ($el -match 'Default User') -and ($auth -match 'Get-CursorAuthTempRoot') -and ($gm -match 'Test-TunnelBannerIsWindows -Banner \$banner') -and ($el -match 'preserve_open_windows') -and ($el -notmatch 'pre_launch_agent_or_new_window') -and ($diag -match 'not found for this Windows user')))
}

. "$smartPack\editor-launch.ps1"
$script:LaptopUser='NoSuchUser'
$u=$env:USERNAME; $env:USERNAME='Administrator'
$cli=Ensure-EditorOnPath 'cursor'
$env:USERNAME=$u
Write-Output ("CURSOR_ADMIN_SIM_OK={0}" -f [int]([bool]($cli -and (Test-Path $cli))))
Write-Output ("CURSOR_ADMIN_SIM_PATH={0}" -f $cli)

. "$repo\publish\Get-DeployCredentials.ps1"
Write-Output ("SMART_LOCAL_PS1={0}" -f [int](Test-Path "$repo\publish\smart-deploy.local.ps1"))
Write-Output ("SMART_PW_LEN={0}" -f $(if(Get-SmartSudoPassword){(Get-SmartSudoPassword).Length}else{0}))
Write-Output ("SEPIDZ_PW_LEN={0}" -f $(if(Get-SepidzSudoPassword){(Get-SepidzSudoPassword).Length}else{0}))

python -u "$repo\scripts\tmp\precise-probe.py"
