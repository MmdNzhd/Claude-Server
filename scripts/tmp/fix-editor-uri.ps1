Set-Location 'D:\Smart\Claude-Code-Server'
# what does the test assert?
Select-String -Path scripts\client\tests\test-git-mode-deep.ps1 -Pattern 'folder-uri|editor-launch\.sh' -Context 2,2
Write-Output '=== editor-launch.sh matches ==='
Select-String -Path scripts\client\editor-launch.sh -Pattern 'folder-uri|vscode-remote|folderUri' 
Write-Output '=== editor-launch.ps1 ==='
Select-String -Path scripts\client\editor-launch.ps1 -Pattern 'folder-uri|vscode-remote|folderUri' | Select-Object -First 10
