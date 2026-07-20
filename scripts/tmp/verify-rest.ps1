$root='D:\Smart\Claude-Code-Server\scripts\client'
Write-Output '=== Mac soft_fail /6 block ==='
$g=Get-Content "$root\git-mode.sh"
790..830 | ForEach-Object { "{0,4}|{1}" -f $_, $g[$_-1] }
Write-Output '=== Mac ORPHAN protect ==='
Select-String -Path "$root\git-mode.sh" -Pattern 'ORPHAN|bg_pid|pkill' | Select-Object -First 25 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== Win menu non-ascii ==='
Select-String -Path "$root\windows\connect.ps1" -Pattern 'non_ascii|non-ASCII|KeyChar' | Select-Object -First 20 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== Write-ConnectSessionContext ==='
Select-String -Path "$root\windows\connect.ps1" -Pattern 'Write-ConnectSessionContext|editorOpened|alreadyDown|ActiveProjectId' | Select-Object -First 30 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== CLEAR_MOUNT Reason ==='
Select-String -Path "$root\windows\connect.ps1","$root\git-mode.ps1","$root\mac\connect.sh" -Pattern 'CLEAR_MOUNT|Reason=' | Select-Object -First 20 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
