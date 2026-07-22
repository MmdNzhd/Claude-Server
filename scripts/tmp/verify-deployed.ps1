$pack = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260720\windows'
Write-Host "PACK=$pack"
Write-Host ("ver=" + (Get-Content "$pack\connect-version.txt" -Raw).Trim())
Select-String -Path "$pack\git-mode.ps1" -Pattern '\[int\]\$Pid|TunnelPid|StopEditor' | Select-Object -First 8 | ForEach-Object { Write-Host ("GM:{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
Select-String -Path "$pack\connect-ui.ps1" -Pattern 'AllowEmptyString|Get-WindowsSystemProxy|Write-Host \$line' | Select-Object -First 10 | ForEach-Object { Write-Host ("UI:{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
Select-String -Path "$pack\connect.ps1" -Pattern 'TunnelPid|Apply-ConnectProxy|ConnectVersion' | Select-Object -First 8 | ForEach-Object { Write-Host ("CN:{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
# old folder still .9?
$old = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'
if (Test-Path $old) {
  Write-Host ("OLD_VER=" + (Get-Content "$old\connect-version.txt" -Raw).Trim())
  Write-Host 'NOTE: running connect.bat from 20260717 will auto-update from server to .11'
}
