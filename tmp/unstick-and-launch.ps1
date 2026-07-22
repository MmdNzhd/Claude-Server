$ErrorActionPreference = 'Continue'
$launchDir = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
$bat = Join-Path $launchDir 'connect.bat'
Write-Output '==== KILL stale Connect (not Cursor) ===='
$killed = @()
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='cmd.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -and (
      $_.CommandLine -match 'connect-boot\.ps1|\\connect\.ps1|connect\.bat' -or
      ($_.CommandLine -match 'claude-publish\\claude-code-client' -and $_.CommandLine -match 'connect')
    )
  } |
  ForEach-Object {
    Write-Output ("kill connect pid={0}" -f $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    $killed += $_.ProcessId
  }
Start-Sleep -Milliseconds 500
Write-Output '==== KILL orphan ssh -R (all local reverse tunnels) ===='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match '-R\s+\d+:localhost:22' } |
  ForEach-Object {
    [void]($_.CommandLine -match '-R\s+(\d+):localhost:22')
    Write-Output ("kill ssh -R pid={0} port={1}" -f $_.ProcessId, $Matches[1])
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Start-Sleep -Seconds 1
Write-Output '==== remaining ssh -R ===='
$left = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match '-R\s+\d+:localhost:22' })
Write-Output ("count=" + $left.Count)
Write-Output '==== VERSION ===='
Get-Content (Join-Path $launchDir 'connect-version.txt')
Write-Output '==== LAUNCH connect.bat ===='
if (-not (Test-Path $bat)) { throw "missing $bat" }
# Mark log watermark
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$before = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
Set-Content -Path (Join-Path $env:TEMP 'claude-connect-launch-mark.txt') -Value $before -Encoding ASCII
Start-Process -FilePath $bat -WorkingDirectory $launchDir
Write-Output ("LAUNCHED bat=$bat mark_bytes=$before")
Write-Output 'Waiting for UAC approve + session start...'
