$ErrorActionPreference='Continue'
$fail=0
function Ok($m){ Write-Host "OK  $m" }
function Bad($m){ Write-Host "BAD $m"; $script:fail++ }

$repo='D:\Smart\Claude-Code-Server\scripts\client'
$cc='C:\Users\Smart\Desktop\Claude-Connect'

foreach($pair in @(
  @('repo', "$repo\windows\connect-version.txt", "$repo\windows\connect.ps1", "$repo\git-mode.ps1", "$repo\editor-launch.ps1"),
  @('CC', "$cc\connect-version.txt", "$cc\connect.ps1", "$cc\git-mode.ps1", "$cc\editor-launch.ps1")
)){
  $name,$vf,$cp,$gm,$el = $pair
  $ver=(Get-Content $vf -Raw).Trim()
  $cv = if(Select-String -Path $cp -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1){ (Select-String -Path $cp -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1).Matches[0].Groups[1].Value } else {'?'}
  $marks = @{
    reseed = (Select-String -Path $gm -Pattern 'Test-TunnelNeedsProxyReseed' -Quiet)
    scoped = (Select-String -Path $gm -Pattern 'Never mass-kill' -Quiet)
    proxyArgs = (Select-String -Path $el -Pattern 'Get-CursorProxyLaunchArgs' -Quiet)
    relaunch = (Select-String -Path $el -Pattern 'proxy_settings_changed' -Quiet)
    noPreserve = -not (Select-String -Path $el -Pattern 'preserved_open_windows' -Quiet)
    noAlign = -not (Select-String -Path $el -Pattern 'Get-RunningCursorProxySocksPort|CURSOR_PROXY_ALIGN' -Quiet)
    noListenDown = -not (Select-String -Path $gm -Pattern 'listen_down' -Quiet)
  }
  $all = ($ver -eq '20260721.38' -and $cv -eq '20260721.38' -and ($marks.Values | Where-Object { -not $_ }).Count -eq 0)
  $detail = ($marks.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
  if($all){ Ok "$name ver=$ver cv=$cv $detail" } else { Bad "$name ver=$ver cv=$cv $detail" }
}

foreach($f in @("$repo\editor-launch.ps1","$repo\git-mode.ps1","$repo\windows\connect.ps1","$cc\editor-launch.ps1","$cc\git-mode.ps1")){
  $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$null,[ref]$e)
  if($e -and $e.Count){ Bad "parse $f"; $e|Select-Object -First 3 } else { Ok "parse $(Split-Path $f -Leaf)" }
}

# hash repo==CC
foreach($p in @(
  @("$repo\editor-launch.ps1","$cc\editor-launch.ps1"),
  @("$repo\git-mode.ps1","$cc\git-mode.ps1"),
  @("$repo\windows\connect.ps1","$cc\connect.ps1")
)){
  if((Get-FileHash $p[0]).Hash -eq (Get-FileHash $p[1]).Hash){ Ok "hash $(Split-Path $p[1] -Leaf)" } else { Bad "hash mismatch $(Split-Path $p[1] -Leaf)" }
}

if($fail -eq 0){ 'ROLLBACK_38_LOCAL_OK' } else { "FAILS=$fail" }
