Select-String -Path 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' -Pattern 'claude-self-heal|laptop-exec|server|Install|/usr/local' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '---'
Get-ChildItem 'D:\Smart\Claude-Code-Server\publish\*sepidz*','D:\Smart\Claude-Code-Server\publish\*install*' -ErrorAction SilentlyContinue | ForEach-Object Name
