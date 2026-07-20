Write-Host '=== connect-related processes ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'connect\.ps1|connect\.bat|connect-ui|claude-connect|claude-code-sepidz' } |
  Select-Object ProcessId, CreationDate, @{n='Cmd';e={ if($_.CommandLine.Length -gt 180){$_.CommandLine.Substring(0,180)} else {$_.CommandLine} }} |
  Format-List

Write-Host '=== ssh reverse tunnel procs ==='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match '21002|21003|R 210' } |
  Select-Object ProcessId, @{n='Cmd';e={ if($_.CommandLine.Length -gt 200){$_.CommandLine.Substring(0,200)} else {$_.CommandLine} }} |
  Format-List

Write-Host '=== who locks log? (open handles via .NET try) ==='
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
try {
  $fs = [IO.File]::Open($local, 'Open', 'ReadWrite', 'None')
  $fs.Close()
  Write-Host 'log exclusive open: OK (not exclusively locked now)'
} catch {
  Write-Host ("log exclusive open FAIL: {0}" -f $_.Exception.Message)
}
try {
  $fs = [IO.File]::Open($local, 'Append', 'Write', 'Read')
  $fs.Close()
  Write-Host 'log append+Read share: OK'
} catch {
  Write-Host ("log append FAIL: {0}" -f $_.Exception.Message)
}

Write-Host '=== Initialize-ConnectLog share mode in desktop .11 ==='
$ui = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\connect-ui.ps1'
Select-String -Path $ui -Pattern 'StreamWriter|FileShare|ConnectLogWriter' | Select-Object -First 15 |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
