$f = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
Select-String -Path $f -Pattern 'ORPHAN_TUNNEL|STALE_FORWARD|Stop-Process|Clear-Session|Close-.*Editor|editorOpened|cursor' -CaseSensitive:$false |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '---- editor-launch ----'
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Pattern 'Stop-Process|Get-Process|Close|kill' -CaseSensitive:$false |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
