$lines = Get-Content scripts\client\connect-ui.ps1
for ($i=213; $i -lt [Math]::Min(320,$lines.Count); $i++) {
  Write-Host ('{0,4}|{1}' -f ($i+1), $lines[$i])
}
