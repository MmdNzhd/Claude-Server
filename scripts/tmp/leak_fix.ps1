$ErrorActionPreference='Stop'
$repoUpd='D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
$src='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code'
# ensure repo updater has cleanup
$hasCleanup = (Select-String -Path $repoUpd -Pattern "Safety: never leave nested" -Quiet)
Write-Host "REPO_HAS_CLEANUP=$hasCleanup"
$tree=Join-Path $env:TEMP 'leak-fix-tree'
if(Test-Path $tree){Remove-Item $tree -Recurse -Force}
Copy-Item $src $tree -Recurse -Force
$win=Join-Path $tree 'windows'
Copy-Item $repoUpd (Join-Path $win 'connect-update.ps1') -Force
Set-Content (Join-Path $win 'connect-version.txt') '20260717.8'
$log=Join-Path $env:TEMP 'leakfix.log'
$p=Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $win 'connect-update.ps1'),'-ScriptDir',$win) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $log -Raw)+'')
$kids = (Get-ChildItem $win -Directory | ForEach-Object { $_.Name }) -join ','
Write-Host "WIN_DIRS=$kids"
Write-Host ("leakMac="+(Test-Path (Join-Path $win 'mac'))+" leakSrv="+(Test-Path (Join-Path $win 'server')))
Write-Host ("ver="+(Get-Content (Join-Path $win 'connect-version.txt') -Raw).Trim())
Write-Host ("macVer="+(Get-Content (Join-Path $tree 'mac\connect-version.txt') -Raw).Trim())
Write-Host ("sourceOK="+((Get-Content $log -Raw) -match 'sepidz@192\.168\.250\.70'))
if(Test-Path (Join-Path $win 'mac')){throw 'STILL_MAC_LEAK'}
if(Test-Path (Join-Path $win 'server')){throw 'STILL_SRV_LEAK'}
Write-Host 'LEAK_FIX_PASS'
