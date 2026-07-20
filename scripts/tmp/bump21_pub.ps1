$ErrorActionPreference='Stop'
$ver='20260719.21'
Set-Content scripts\client\windows\connect-version.txt $ver
if(Test-Path scripts\client\mac\connect-version.txt){ Set-Content scripts\client\mac\connect-version.txt $ver }
$cp=[IO.File]::ReadAllText((Resolve-Path 'scripts\client\windows\connect.ps1'))
$cp2=[regex]::Replace($cp, "\`$script:ConnectVersion = '20260719\.\d+'", "`$script:ConnectVersion = '$ver'", 1)
if($cp2 -eq $cp){ throw 'ver bump fail' }
[IO.File]::WriteAllText((Resolve-Path 'scripts\client\windows\connect.ps1'), $cp2)

# parse update
$e=$null;$t=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\client\windows\connect-update.ps1'),[ref]$t,[ref]$e)
if($e -and $e.Count){ $e|%{$_.ToString()}; throw 'still broken' }
if(Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'Invoke-BundleDownloadfunction' -Quiet){ throw 'dup still there' }
Write-Host "OK ver=$ver parse_update_ok"
