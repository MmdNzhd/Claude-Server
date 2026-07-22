$ErrorActionPreference='Continue'
$checks=@()
function Add-Check($n,$ok,$detail){ $script:checks += [pscustomobject]@{name=$n; ok=[bool]$ok; detail="$detail"} }

$vRepo = (Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim()
$vCC   = (Get-Content 'C:\Users\Smart\Desktop\Claude-Connect\windows\connect-version.txt' -Raw).Trim()
$vPubPath = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260721\windows\connect-version.txt'
$vPub  = if(Test-Path $vPubPath){ (Get-Content $vPubPath -Raw).Trim() } else { 'missing' }
Add-Check 'version_repo' ($vRepo -eq '20260721.42') $vRepo
Add-Check 'version_claude_connect' ($vCC -eq '20260721.42') $vCC
Add-Check 'version_publish' ($vPub -eq '20260721.42') $vPub

$files=@('windows\connect.ps1','windows\connect-update.ps1','git-mode.ps1','editor-launch.ps1','mac\connect.sh','mac\connect-update.sh','git-mode.sh','editor-launch.sh')
$mismatch=@()
foreach($f in $files){
  $a="D:\Smart\Claude-Code-Server\scripts\client\$f"
  $b="C:\Users\Smart\Desktop\Claude-Connect\$f"
  if(-not (Test-Path $a) -or -not (Test-Path $b)){ $mismatch += "$f missing"; continue }
  $ha=(Get-FileHash $a -Algorithm SHA256).Hash
  $hb=(Get-FileHash $b -Algorithm SHA256).Hash
  if($ha -ne $hb){ $mismatch += $f }
}
Add-Check 'hashes_repo_eq_claude_connect' ($mismatch.Count -eq 0) ($(if($mismatch){ $mismatch -join ',' } else { 'all_match' }))

$el = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Raw
Add-Check 'preserve_open_windows' ($el -match 'preserved_open_windows') 'marker'
Add-Check 'proxy_align_no_kill' (($el -match 'CURSOR_PROXY_ALIGN|prefer_running_cli') -and ($el -match 'Get-RunningCursorProxySocksPort')) 'ok'

. 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$cli = Get-RunningCursorProxySocksPort
$prof = Get-CursorRemoteProfileDir
$settings = Join-Path $prof 'User\settings.json'
$sp=$null; $proxyMode=$null
if(Test-Path $settings){
  $j=Get-Content -Raw $settings|ConvertFrom-Json
  if($j.'http.proxy' -match ':(\d+)'){ $sp=[int]$Matches[1] }
  $proxyMode = $j.'http.proxySupport'
}
Add-Check 'cli_settings_port_match' ($cli -and $sp -and $cli -eq $sp) "cli=$cli settings=$sp"
Add-Check 'proxy_override' ($proxyMode -eq 'override') "$proxyMode"

$ssh = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | Where-Object { $_.CommandLine -match '10808|1908' }
$hasL = @($ssh | Where-Object { $_.CommandLine -match '-L.*10808' }).Count -gt 0
$hasD = @($ssh | Where-Object { $_.CommandLine -match '(^|\s)-D(\s|=)' }).Count -gt 0
Add-Check 'tunnel_has_L_10808' $hasL ("ssh_count=" + @($ssh).Count)
Add-Check 'tunnel_no_legacy_D' (-not $hasD) ("hasD=$hasD")

$curs = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'")
Add-Check 'cursor_alive' ($curs.Count -ge 1) ("procs=" + $curs.Count)

# soft-stop must not fire for proxy_settings_changed
Add-Check 'no_proxy_softstop_code' ($el -notmatch 'LAUNCH_KILL:\s*proxy_settings_changed') 'ok'

$checks | Format-Table -AutoSize | Out-String -Width 180
$fail = @($checks | Where-Object { -not $_.ok })
if($fail.Count -eq 0){ 'COMPLETE_ALL_GREEN' } else { 'FAIL_COUNT=' + $fail.Count; $fail | Format-Table -AutoSize | Out-String }
