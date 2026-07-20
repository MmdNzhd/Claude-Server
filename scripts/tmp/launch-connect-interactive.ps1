$ErrorActionPreference = 'Continue'
$wd = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
$task = 'ClaudeConnectManualTrack'

$user = $env:USERNAME
try {
  $e = Get-Process explorer -ErrorAction Stop | Select-Object -First 1
  $owner = (Get-CimInstance Win32_Process -Filter "ProcessId=$($e.Id)").GetOwner()
  if ($owner.User) { $user = $owner.User }
} catch {}

$tr = "cmd.exe /c cd /d `"$wd`" && connect.bat"
cmd /c "schtasks /Delete /F /TN $task" | Out-Null
$createOut = cmd /c "schtasks /Create /F /TN $task /TR `"$tr`" /SC ONCE /ST 00:00 /RU $user /RL LIMITED /IT"
Write-Host "CREATE_USER=$user"
Write-Host "CREATE_OUT=$createOut EC=$LASTEXITCODE"
$runOut = cmd /c "schtasks /Run /TN $task"
Write-Host "RUN_OUT=$runOut EC=$LASTEXITCODE"
Write-Host "BEFORE_BYTES=$((Get-Item $log).Length) MTIME=$((Get-Item $log).LastWriteTime)"
Write-Host "LOCAL_VER=$((Get-Content (Join-Path $wd 'connect-version.txt') -Raw).Trim())"
