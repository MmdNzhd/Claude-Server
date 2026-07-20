$ErrorActionPreference = 'Continue'
$src = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260720\windows'
$dst = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'claude-code-client-20260717\\windows' } |
  ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
Start-Sleep 2
Get-ChildItem $src -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $dst $_.Name) -Force }
Write-Host "VER=$((Get-Content (Join-Path $dst 'connect-version.txt') -Raw).Trim())"

$task = 'ClaudeConnectManualTrack'
$user = 'Smart'
try {
  $e = Get-Process explorer | Select-Object -First 1
  $o = (Get-CimInstance Win32_Process -Filter "ProcessId=$($e.Id)").GetOwner()
  if ($o.User) { $user = $o.User }
} catch {}
$tr = "cmd.exe /c cd /d `"$dst`" && connect.bat"
cmd /c "schtasks /Delete /F /TN $task" | Out-Null
cmd /c "schtasks /Create /F /TN $task /TR `"$tr`" /SC ONCE /ST 23:59 /RU $user /RL LIMITED /IT" | Out-Null
cmd /c "schtasks /Run /TN $task"
Write-Host "LAUNCHED user=$user"
Write-Host "MARK=$(Get-Date -Format 'HH:mm:ss')"
