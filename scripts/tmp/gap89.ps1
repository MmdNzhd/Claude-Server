$ErrorActionPreference='Continue'
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
$sid='45c2722335a7'
$sess=@(Select-String -Path $today -Pattern ("\["+$sid+"\]") | ForEach-Object { $_.Line })

Write-Host '=== ALL lines from Mounting begin to Opening Cursor ==='
$in=$false
foreach($l in $sess){
  if($l -match 'STEP begin: Mounting'){ $in=$true }
  if($in){
    Write-Host $l.Substring(0,[Math]::Min(240,$l.Length))
  }
  if($l -match 'STEP end: Opening Cursor'){ break }
}

Write-Host "`n=== live now ==="
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.ps1' } |
  ForEach-Object {
    Write-Host ("PID={0} age={1:N0}s {2}" -f $_.ProcessId, ((Get-Date)-$_.CreationDate).TotalSeconds, $_.CommandLine)
  }

# current laptop-exec / mount on server via tunnel if possible
Write-Host "`n=== server conf via laptop-exec ==="
