$root='D:\Smart\Claude-Code-Server\scripts\client'
Write-Output '=== Win session state that would die on restart ==='
Select-String -Path "$root\windows\connect.ps1","$root\git-mode.ps1" -Pattern 'BgTunnel|script:Tunnel|elevat|Start-Process|Admin|finally|Stop-Session|editorOpened|EditorSeen|ControlMaster|job |Register-ObjectEvent|Timer|while \(\$true\)|sessionLoop' | Select-Object -First 55 | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '=== Quiet switch on update? ==='
Select-String -Path "$root\windows\connect-update.ps1" -Pattern 'Quiet|Write-UpdateMsg|Write-Host' | Select-Object -First 25 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== staging dir path ==='
Select-String -Path "$root\windows\connect-update.ps1" -Pattern 'StagingDir|client-update|TEMP' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== elevated relaunch path ==='
Select-String -Path "$root\windows\connect.ps1" -Pattern 'IsAdministrator|Start-Process.*-Verb RunAs|elevat' | Select-Object -First 20 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
