$c = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
885..1020 | ForEach-Object { '{0,4}|{1}' -f $_, $c[$_-1] }
Write-Host '==== Clear callers ===='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\*.ps1','D:\Smart\Claude-Code-Server\scripts\client\windows\*.ps1' -Pattern 'Clear-CursorProxySettings' | ForEach-Object { "$($_.Filename):$($_.LineNumber): $($_.Line.Trim())" }
Write-Host '==== Get-SocksProxyPort ===='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'function Get-SocksProxyPort|19080|TunnelSlot' | Select-Object -First 20 | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
