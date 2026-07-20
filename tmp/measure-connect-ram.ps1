$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
Write-Host "logDir=$logDir"
if (Test-Path $logDir) {
  Get-ChildItem $logDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Host
} else {
  Write-Host 'no local connect logs dir'
}
Write-Host '--- processes ---'
Get-Process powershell,ssh,scp,sshd,Cursor -ErrorAction SilentlyContinue |
  Select-Object Name, Id,
    @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,1)}},
    @{N='PM_MB';E={[math]::Round($_.PrivateMemorySize64/1MB,1)}} |
  Sort-Object WS_MB -Descending |
  Format-Table -AutoSize | Out-String | Write-Host
Write-Host '--- ssh cmdline ---'
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  ForEach-Object {
    $c = $_.CommandLine
    if ($c -and $c.Length -gt 180) { $c = $c.Substring(0,180) + '...' }
    "{0}  {1}" -f $_.ProcessId, $c
  }
