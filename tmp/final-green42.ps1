$ErrorActionPreference = 'Continue'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client'
$cc = 'C:\Users\Smart\Desktop\Claude-Connect'
$pub = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260721'
$checks = @()
function Add($n,$ok,$d){ $script:checks += [pscustomobject]@{name=$n; ok=[bool]$ok; detail="$d"} }

$vRepo = (Get-Content "$repo\windows\connect-version.txt" -Raw).Trim()
$vCC = (Get-Content "$cc\connect-version.txt" -Raw).Trim()
$vPub = (Get-Content "$pub\windows\connect-version.txt" -Raw).Trim()
Add 'repo_ver' ($vRepo -eq '20260721.42') $vRepo
Add 'claude_connect_ver' ($vCC -eq '20260721.42') $vCC
Add 'publish_smart_ver' ($vPub -eq '20260721.42') $vPub

$pairs = @(
  @("$repo\windows\connect.ps1", "$cc\connect.ps1"),
  @("$repo\windows\connect-update.ps1", "$cc\connect-update.ps1"),
  @("$repo\git-mode.ps1", "$cc\git-mode.ps1"),
  @("$repo\editor-launch.ps1", "$cc\editor-launch.ps1"),
  @("$repo\git-mode.sh", "$cc\mac\git-mode.sh"),
  @("$repo\editor-launch.sh", "$cc\mac\editor-launch.sh"),
  @("$repo\windows\connect.ps1", "$pub\windows\connect.ps1"),
  @("$repo\editor-launch.ps1", "$pub\editor-launch.ps1"),
  @("$repo\git-mode.ps1", "$pub\git-mode.ps1")
)
$bad = @()
foreach ($p in $pairs) {
  if (-not (Test-Path $p[0]) -or -not (Test-Path $p[1])) { $bad += "missing $($p[1])"; continue }
  if ((Get-FileHash $p[0]).Hash -ne (Get-FileHash $p[1]).Hash) { $bad += (Split-Path $p[1] -Leaf) }
}
Add 'hashes_repo_cc_pub' ($bad.Count -eq 0) ($(if ($bad) { $bad -join ',' } else { 'all_match' }))

. "$repo\editor-launch.ps1"
$cli = Get-RunningCursorProxySocksPort
$sp = $null
$settings = Join-Path (Get-CursorRemoteProfileDir) 'User\settings.json'
if (Test-Path $settings) {
  $j = Get-Content -Raw $settings | ConvertFrom-Json
  if ($j.'http.proxy' -match ':(\d+)') { $sp = [int]$Matches[1] }
}
Add 'cli_settings_match' ($cli -and $sp -and $cli -eq $sp) "cli=$cli settings=$sp"

$ssh = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | Where-Object { $_.CommandLine -match '10808|1908' })
Add 'tunnel_L' ((@($ssh | Where-Object { $_.CommandLine -match '-L.*10808' }).Count -gt 0)) ("n=$($ssh.Count)")
Add 'no_D' ((@($ssh | Where-Object { $_.CommandLine -match '(^|\s)-D(\s|=)' }).Count -eq 0)) 'ok'
$curs = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'")
Add 'cursor_alive' ($curs.Count -ge 1) "procs=$($curs.Count)"

$el = Get-Content "$repo\editor-launch.ps1" -Raw
Add 'preserve_windows' ($el -match 'preserved_open_windows') 'ok'
Add 'align_running_cli' ($el -match 'Get-RunningCursorProxySocksPort' -and $el -match 'CURSOR_PROXY_ALIGN|prefer_running_cli') 'ok'
Add 'no_proxy_kill' ($el -notmatch 'LAUNCH_KILL:\s*proxy_settings_changed') 'ok'

$checks | Format-Table -AutoSize | Out-String -Width 200
$fail = @($checks | Where-Object { -not $_.ok })
if ($fail.Count -eq 0) { 'COMPLETE_ALL_GREEN' } else { 'FAIL=' + $fail.Count; $fail | Format-Table -AutoSize | Out-String }
