$today = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
Select-String -Path $today -Pattern '45c2722335a7' | Where-Object { $_.Line -match '14:03:3|14:04:|14:05:0' } | ForEach-Object {
  $_.Line.Substring(0, [Math]::Min(220, $_.Line.Length))
}
Write-Host '--- other sessions in gap window ---'
Select-String -Path $today -Pattern '\[2026-07-19 14:0[34]' | Select-Object -First 80 | ForEach-Object {
  $_.Line.Substring(0, [Math]::Min(180, $_.Line.Length))
}
