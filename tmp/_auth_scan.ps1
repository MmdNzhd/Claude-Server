$files = @(
  'scripts\client\git-mode.sh',
  'scripts\client\git-mode.ps1',
  'scripts\client\cursor-auth-laptop.ps1',
  'scripts\client\editor-launch.ps1',
  'scripts\client\editor-launch.sh'
)
$pat = 'AUTH_RELAUNCH|CLAUDE_SERVER|CURSOR_AUTH|machineid|machineId|golden|folder-uri|folderUri|agent.?home|Agent home|Get-CursorRemoteProfileDir|user-data-dir|vscode-remote'
foreach ($f in $files) {
  if (-not (Test-Path $f)) { Write-Output "MISSING $f"; continue }
  Select-String -Path $f -Pattern $pat | ForEach-Object {
    $line = $_.Line.Trim()
    if ($line.Length -gt 220) { $line = $line.Substring(0,220) + '...' }
    Write-Output ("{0}:{1}:{2}" -f $f, $_.LineNumber, $line)
  }
}
