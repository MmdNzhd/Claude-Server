$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
Write-Output '=== Ensure-EditorOnPath full ==='
(Get-Content (Join-Path $root 'scripts\client\editor-launch.ps1'))[33..55]
Write-Output '=== tests mentioning Ensure-Editor / CURSOR_NOT ==='
Get-ChildItem (Join-Path $root 'scripts\client\tests') -Filter '*.ps1' | ForEach-Object {
  $h=Select-String -Path $_.FullName -Pattern 'Ensure-EditorOnPath|CURSOR_NOT|Local\\Programs\\cursor' -SimpleMatch:$false
  if($h){ Write-Output $_.Name; $h | ForEach-Object { "  $($_.LineNumber):$($_.Line.Trim())" } }
}
Write-Output '=== connect.ps1 CURSOR_NOT_FOUND context ==='
Select-String -Path (Join-Path $root 'scripts\client\windows\connect.ps1') -Pattern 'CURSOR_NOT|EditorOnPath|editor not found|EditorCmd' -Context 2,3 |
  Select-Object -First 20 | ForEach-Object {
    if($_.Context.PreContext){ $_.Context.PreContext | ForEach-Object { "  |$_" } }
    ">>$($_.Line)"
    if($_.Context.PostContext){ $_.Context.PostContext | ForEach-Object { "  |$_" } }
  }
Write-Output '=== versions / smart sudo ==='
(Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')
Write-Output ("smart_pw_len=" + ($(if(Get-SmartSudoPassword){(Get-SmartSudoPassword).Length}else{0})))
Write-Output ("sepidz_pw_len=" + ($(if(Get-SepidzSudoPassword){(Get-SepidzSudoPassword).Length}else{0})))
