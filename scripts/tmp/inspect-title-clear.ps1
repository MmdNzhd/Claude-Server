Set-Location D:\Smart\Claude-Code-Server
Select-String -Path scripts/client/windows/connect.ps1,scripts/client/connect-ui.ps1 -Pattern 'Set-ConnectTitle|function Set-ConnectTitle|Write-Host.*git:HIDE|ConnectTitle' |
  ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Filename,$_.LineNumber,$_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length))) }
Write-Host '--- finally/clear ---'
Get-Content scripts/client/windows/connect.ps1 | Select-Object -Skip 1990 -First 50 | ForEach-Object -Begin {$i=1991} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }
Write-Host '--- Stop-RemoteEditor ---'
$lines=Get-Content scripts/client/editor-launch.ps1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'function Stop-RemoteEditor'){
    for($j=$i;$j -lt [Math]::Min($i+50,$lines.Count);$j++){ Write-Host ("{0}|{1}" -f ($j+1),$lines[$j]) }
    break
  }
}
Write-Host '--- update version check ---'
Select-String -Path scripts/client/windows/connect-update.ps1 -Pattern 'connect-version|up to date|CLIENT|remoteVer|RemoteVersion' | Select-Object -First 25 |
  ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber,$_.Line.Trim()) }
