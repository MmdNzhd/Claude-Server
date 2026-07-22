$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
& "$Repo\publish\publish.ps1" -SmartOnly -SkipVersionBump
if ($LASTEXITCODE -ne 0) { throw "publish failed" }
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260720'
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$old = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717'
$files = @('connect.bat','connect-boot.ps1','connect-version.txt','connect-update.ps1','connect.ps1','connect-rider.bat','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1','connect-ui.ps1','connect-diagnostic.ps1')
foreach ($f in $files) {
  Copy-Item (Join-Path $pub "windows\$f") (Join-Path $desk $f) -Force
}
# also force-sync the folder user keeps launching
if (Test-Path $old) {
  robocopy $pub $old /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
}
$ver = (Get-Content (Join-Path $desk 'connect-version.txt') -Raw).Trim()
if ($ver -ne '20260720.26') { throw "desk ver $ver" }
# prove elev fix in published connect.ps1
$raw = Get-Content (Join-Path $desk 'connect.ps1') -Raw
if ($raw -notmatch 'ClaudeConnectBootMutex' -or $raw -notmatch "connect-boot\.ps1") { throw 'elev fix missing on desk' }
Write-Host "SHIP_OK desk=$ver mutex=check next"
try { $null = [System.Threading.Mutex]::OpenExisting('Global\ClaudeConnect'); Write-Host 'mutex=HELD' } catch { Write-Host 'mutex=FREE' }
