Select-String -Path 'scripts/client/tests/*.ps1' -Pattern 'Assert \(\$true' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '--- PushConf quoting tests ---'
Select-String -Path 'scripts/client/tests/*.ps1' -Pattern 'Push-ServerConnectConf|Escape-Bash|single.quot|Farzad|LAPTOP_USER|quoting' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '--- SshX LASTEXITCODE ---'
Select-String -Path 'scripts/client/windows/connect.ps1','scripts/client/git-mode.ps1' -Pattern 'function SshX|LASTEXITCODE|Invoke-SshXCore' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '--- CIM TTL ---'
Select-String -Path 'scripts/client/editor-launch.ps1' -Pattern 'EditorCimCache|CimCache|TTL|Expires|ForceRefresh|cache_hit' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '--- Get-RemoteEditorStateExplain ---'
Select-String -Path 'scripts/client/editor-launch.ps1','scripts/client/connect-ui.ps1' -Pattern 'Get-RemoteEditorStateExplain|HEARTBEAT|Format-EditorProcessCommandLine' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '--- Close log delete ---'
Select-String -Path 'scripts/client/connect-ui.ps1' -Pattern 'Remove-Item.*ConnectLog|Delete.*log|durable|ConnectLogPath|claude-connect-' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '--- RunAs / AdminFix docs ---'
Select-String -Path 'docs/client-connect.md','publish/README.txt','CLAUDE.md' -Pattern 'RunAs|self-elevate|AdminFix|temp buffer|deleted when|deleted on|durable local' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
