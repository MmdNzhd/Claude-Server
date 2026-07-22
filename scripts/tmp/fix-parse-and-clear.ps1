Set-Location D:\Smart\Claude-Code-Server
$tok=$null;$err=$null
$null=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/client/windows/connect.ps1'),[ref]$tok,[ref]$err)
if ($err) {
  Write-Host "PARSE ERRORS: $($err.Count)" -ForegroundColor Red
  foreach ($e in $err) {
    Write-Host ("  L{0}:{1} {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) -ForegroundColor Red
    Write-Host ("    text=[{0}]" -f $e.Extent.Text) -ForegroundColor DarkYellow
  }
} else { Write-Host 'PARSE OK' -ForegroundColor Green }

Write-Host "`n=== Clear-SessionMount ===" -ForegroundColor Cyan
$lines = Get-Content scripts/client/git-mode.ps1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Clear-SessionMount') {
    for ($j=$i; $j -lt [Math]::Min($i+35,$lines.Count); $j++) {
      Write-Host ("{0}|{1}" -f ($j+1), $lines[$j])
    }
    break
  }
}

# Check for smart quotes / BOM issues near ConnectVersion
Write-Host "`n=== Around ConnectVersion / proxy wire ===" -ForegroundColor Cyan
Get-Content scripts/client/windows/connect.ps1 | Select-Object -Skip 90 -First 20 | ForEach-Object -Begin {$i=91} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }
Get-Content scripts/client/windows/connect.ps1 | Select-Object -Skip 1065 -First 25 | ForEach-Object -Begin {$i=1066} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }
