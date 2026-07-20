$src='D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1'
$dests=@(
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\cursor-auth-laptop.ps1'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\cursor-auth-laptop.ps1')
)
foreach($d in $dests){
  if(Test-Path (Split-Path $d -Parent)){
    Copy-Item $src $d -Force
    Write-Output "synced $d"
  } else { Write-Output "skip missing parent $d" }
}
