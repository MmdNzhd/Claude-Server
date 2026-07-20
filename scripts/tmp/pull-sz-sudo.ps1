# Try reading sepidz user logs if we can scp as root via a known path
# Also scan local forensic for AA616 / Unexpected / a.tavakol
$ErrorActionPreference='Continue'
$files = Get-ChildItem 'D:\Smart\Claude-Code-Server\scripts\tmp\*connect*.log' -EA SilentlyContinue
'=== local forensics ==='
$files | ForEach-Object { $_.Name + ' ' + $_.Length }
foreach ($f in $files) {
  $hits = Select-String -Path $f.FullName -Pattern 'AA616|Unexpected error|a\.tavakol|alit|Remove-Item|Agent Execution|Connection Error|session start v20260719\.3' -EA SilentlyContinue |
    Select-Object -Last 20
  if ($hits) {
    "--- $($f.Name) ---"
    $hits | ForEach-Object { $_.Line.Substring(0,[Math]::Min(240,$_.Line.Length)) }
  }
}

# Check when 8.3 fix landed in git log if available
Push-Location 'D:\Smart\Claude-Code-Server'
git log --oneline -5 -- scripts/client/cursor-auth-laptop.ps1 2>$null
Select-String -Path 'scripts/client/cursor-auth-laptop.ps1' -Pattern 'Get-CursorAuthTempRoot|AA616|8\.3' | Select-Object -First 5
Pop-Location
