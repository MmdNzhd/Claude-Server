$ErrorActionPreference='Continue'
$root='D:\Smart\Claude-Code-Server'
function Assert-Match($file,$pat,$label){
  $p=Join-Path $root $file
  $ok = Select-String -Path $p -Pattern $pat -Quiet
  "{0}: {1} | {2}" -f $(if($ok){'OK'}else{'MISS'}), $label, $file
}
Write-Host '==== PRESENCE ===='
Assert-Match 'scripts\client\editor-launch.ps1' 'auth_relaunch_never_kill' 'Win never_kill'
Assert-Match 'scripts\client\editor-launch.ps1' 'hard_refuse_' 'Win hard_refuse'
Assert-Match 'scripts\client\windows\connect.ps1' 'skip_auth_relaunch' 'Win skip_auth_relaunch'
Assert-Match 'scripts\client\editor-launch.sh' 'auth_relaunch soft-stop' 'Mac STILL soft-stop'
Assert-Match 'scripts\client\editor-launch.sh' 'auth_relaunch_never_kill' 'Mac never_kill (expect MISS)'
Assert-Match 'scripts\client\git-mode.ps1' 'CURSOR_PROXY_ALIGN' 'ALIGN in git-mode (expect MISS)'
Assert-Match 'scripts\client\editor-launch.ps1' 'CURSOR_PROXY_ALIGN' 'ALIGN in editor-launch (expect MISS)'
Assert-Match 'scripts\client\sync-desktop.ps1' 'connect-version.txt' 'sync-desktop exists'
Assert-Match 'scripts\server\client-update-policy.json' '.' 'update-policy (expect MISS)'
Assert-Match 'scripts\client\git-mode.ps1' 'Test-NetConnection' 'TNC in git-mode'
Assert-Match 'scripts\client\editor-launch.ps1' 'Clear-CursorProxySettings' 'Win Clear'
Assert-Match 'scripts\client\editor-launch.sh' 'clear_cursor_proxy_settings' 'Mac Clear'

Write-Host '==== LINE ANCHORS ===='
$files=@(
  @{f='scripts\client\editor-launch.ps1'; p='Clear-CursorProxySettings'},
  @{f='scripts\client\editor-launch.ps1'; p='if \(\$script:SocksProxyPort\)'},
  @{f='scripts\client\git-mode.ps1'; p='function Get-SocksProxyPort'},
  @{f='scripts\client\git-mode.ps1'; p='return 19080 \+ \$slot'},
  @{f='scripts\client\git-mode.sh'; p='socks_proxy_port\(\)'},
  @{f='scripts\client\editor-launch.sh'; p='LAUNCH_KILL: auth_relaunch soft-stop'},
  @{f='scripts\client\connect-ui.ps1'; p="\(active\)"},
  @{f='scripts\client\windows\connect.ps1'; p='function Get-ActiveMountId'},
  @{f='scripts\client\windows\connect.ps1'; p='ConnectVersion'}
)
foreach($x in $files){
  $hits=Select-String -Path (Join-Path $root $x.f) -Pattern $x.p | Select-Object -First 3
  foreach($h in $hits){ "{0}:{1}: {2}" -f $x.f,$h.LineNumber,$h.Line.Trim().Substring(0,[Math]::Min(100,$h.Line.Trim().Length)) }
}

Write-Host '==== VERSIONS ===='
$wv=(Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
$mv=if(Test-Path (Join-Path $root 'scripts\client\mac\connect-version.txt')){(Get-Content (Join-Path $root 'scripts\client\mac\connect-version.txt') -Raw).Trim()}else{'MISSING'}
$ps=(Select-String -Path (Join-Path $root 'scripts\client\windows\connect.ps1') -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1).Matches[0].Groups[1].Value
$sh=(Select-String -Path (Join-Path $root 'scripts\client\mac\connect.sh') -Pattern "CONNECT_VERSION='([^']+)'" | Select-Object -First 1).Matches[0].Groups[1].Value
"win_txt=$wv mac_txt=$mv ps1=$ps sh=$sh"
$desk1=Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-version.txt'
$desk2=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt'
foreach($d in @($desk1,$desk2)){ if(Test-Path $d){"DESK $d = $((Get-Content $d -Raw).Trim())"} else {"DESK MISSING $d"} }

Write-Host '==== TNC COUNT ===='
(Select-String -Path (Join-Path $root 'scripts\client\*.ps1'),(Join-Path $root 'scripts\client\windows\*.ps1'),(Join-Path $root 'scripts\client\*\*.ps1') -Pattern 'Test-NetConnection' -ErrorAction SilentlyContinue | Measure-Object).Count

Write-Host '==== skip_auth block present ===='
Select-String -Path (Join-Path $root 'scripts\client\windows\connect.ps1') -Pattern 'skip_auth_relaunch|profile_windows_open' | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
