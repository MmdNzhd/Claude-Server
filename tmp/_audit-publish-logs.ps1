$ErrorActionPreference = 'Continue'
Write-Host ("USERPROFILE=" + $env:USERPROFILE)
$desk = [Environment]::GetFolderPath('Desktop')
Write-Host ("DESKTOP=" + $desk)
$cp = Join-Path $desk 'claude-publish'
if (Test-Path $cp) {
  Write-Host '=== claude-publish ==='
  Get-ChildItem $cp | Format-Table Name, LastWriteTime, Length -AutoSize
  Get-ChildItem $cp -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'connect|cursor-auth|manifest|version' } |
    Select-Object -First 80 FullName, Length, LastWriteTime |
    Format-Table -AutoSize
} else {
  Write-Host 'no claude-publish on Desktop'
}
Write-Host '=== Desktop claude* ==='
Get-ChildItem $desk -Filter '*claude*' -ErrorAction SilentlyContinue | Format-Table Name, LastWriteTime, Mode -AutoSize
# also common live client dirs
$candidates = @(
  (Join-Path $desk 'claude-code'),
  (Join-Path $desk 'claude-code-client'),
  (Join-Path $env:USERPROFILE 'claude-code'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-code'),
  'D:\Smart\Claude-Code-Server\publish'
)
foreach ($c in $candidates) {
  if (Test-Path $c) { Write-Host ("FOUND: " + $c); Get-ChildItem $c -ErrorAction SilentlyContinue | Select-Object -First 20 Name, LastWriteTime | Format-Table -AutoSize }
}
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
Write-Host ("logDir=" + $logDir)
if (Test-Path $logDir) {
  Get-ChildItem $logDir | Sort-Object LastWriteTime -Descending | Select-Object -First 20 | Format-Table Name, Length, LastWriteTime -AutoSize
} else {
  Write-Host 'no log dir'
}
