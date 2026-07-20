# Kill stuck connect sessions for the 20260717 windows package (keep other work)
$target = 'claude-code-client-20260717\windows'
$killed = @()
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -and (
      $_.CommandLine -match [regex]::Escape($target) -or
      ($_.CommandLine -match 'connect\.(bat|ps1)' -and $_.CommandLine -match 'claude-publish\\claude-code-client')
    )
  } |
  ForEach-Object {
    try {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
      $killed += ("{0}:{1}" -f $_.ProcessId, $_.Name)
    } catch {
      $killed += ("fail:{0}:{1}" -f $_.ProcessId, $_.Exception.Message)
    }
  }
Write-Host ("KILLED={0}" -f ($killed -join '; '))

# Also kill mutex holders: any connect.ps1 with ClaudeConnect path under publish
Start-Sleep -Seconds 2

$wd = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
$before = (Get-Item $log).Length
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
Write-Host "RERUN_AT=$stamp BEFORE=$before VER=$((Get-Content (Join-Path $wd 'connect-version.txt') -Raw).Trim())"

# Launch visible so user can answer Y/UAC if needed
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/k','connect.bat' -WorkingDirectory $wd -PassThru
Write-Host "NEW_CMD_PID=$($p.Id)"
