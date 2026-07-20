$ErrorActionPreference='Continue'
$srcPkg = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
$tree = Join-Path $env:TEMP 'sure-leak-inspect'
if (Test-Path $tree) { Remove-Item $tree -Recurse -Force }
Copy-Item $srcPkg $tree -Recurse -Force
$win = Join-Path $tree 'windows'
Write-Host 'UPD_HEAD:'
Select-String -Path (Join-Path $win 'connect-update.ps1') -Pattern 'packageRoot|macDir|server' | Select-Object -First 20 | ForEach-Object { Write-Host $_.Line.Trim() }
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
$log = Join-Path $env:TEMP 'leak.log'
$p = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $win 'connect-update.ps1'),'-ScriptDir',$win) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
[void]$p.WaitForExit(120000)
Write-Host 'OUT:'; Get-Content $log
Write-Host '--- children of windows ---'
Get-ChildItem $win | ForEach-Object { Write-Host ($_.Mode + ' ' + $_.Name) }
if (Test-Path (Join-Path $win 'mac')) {
  Write-Host '--- windows/mac sample ---'
  Get-ChildItem (Join-Path $win 'mac') -Recurse -File | Select-Object -First 15 | ForEach-Object { Write-Host $_.FullName.Substring($win.Length) }
}
if (Test-Path (Join-Path $win 'server')) {
  Write-Host '--- windows/server sample ---'
  Get-ChildItem (Join-Path $win 'server') -Recurse -File | Select-Object -First 15 | ForEach-Object { Write-Host $_.FullName.Substring($win.Length) }
}
Write-Host '--- sibling mac ver ---'
Write-Host ((Get-Content (Join-Path $tree 'mac\connect-version.txt') -Raw).Trim())
