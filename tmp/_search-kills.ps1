$files = @(
  'scripts\client\editor-launch.ps1',
  'scripts\client\editor-launch.sh',
  'scripts\client\windows\connect.ps1',
  'scripts\client\mac\connect.sh',
  'scripts\client\git-mode.ps1',
  'scripts\client\git-mode.sh',
  'scripts\client\users\designer\connect.ps1',
  'scripts\client\users\designer\connect.sh'
)
$pat = 'Stop-Process|taskkill|LAUNCH_KILL|soft-stop|Soft-Stop|SoftStop|Kill-|auth.?relaunch|AuthRelaunch|Clear-SessionMount|clear_session_mount|Cursor\.exe|Get-Process|CloseMainWindow|pkill|killall|\bkill\b'
foreach ($f in $files) {
  if (-not (Test-Path $f)) { Write-Output "MISSING $f"; continue }
  Select-String -Path $f -Pattern $pat | ForEach-Object {
    "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim()
  }
}
