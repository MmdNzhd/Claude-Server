function Show-Func($path, $name) {
  Write-Host "===== FIND $name in $path ====="
  $lines = Get-Content $path
  $start = -1
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ("function\s+$name\b|^\s*$name\s*\(")) { $start=$i; break }
  }
  if ($start -lt 0) { Write-Host "NOT FOUND"; return }
  $end = [Math]::Min($start+80, $lines.Count-1)
  for ($i=$start; $i -le $end; $i++) {
    if ($i -gt $start -and $lines[$i] -match '^function\s+') { break }
    "{0,5}|{1}" -f ($i+1), $lines[$i]
  }
}
Show-Func 'scripts\client\connect-ui.ps1' 'Read-PostDisconnectKey'
Show-Func 'scripts\client\connect-ui.ps1' 'Read-ConnectPrompt'
Show-Func 'scripts\client\connect-ui.ps1' 'Wait-ConnectExit'
Show-Func 'scripts\client\connect-ui.ps1' 'Warn-InvalidProjectRpath'
Show-Func 'scripts\client\connect-ui.ps1' 'Show-ProjectMenu'
Show-Func 'scripts\client\windows\connect.ps1' 'Select-Project'
Write-Host '===== version in ps1 ====='
Select-String -Path 'scripts\client\windows\connect.ps1','scripts\client\windows\connect.bat','scripts\client\mac\connect.sh' -Pattern 'ConnectVersion|CONNECT_VERSION|20260719'
Write-Host '===== tests for session key ====='
Get-ChildItem scripts\client\tests -Filter '*ui*','*session*','*key*','*connect*' -ErrorAction SilentlyContinue | Select-Object Name
Select-String -Path 'scripts\client\tests\*.ps1','scripts\client\tests\*.sh' -Pattern 'Persian|useVk|ReadKey|PostDisconnect|Mutex|KeyAvailable|Enter.*disconnect|default' -CaseSensitive:$false |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)) }
