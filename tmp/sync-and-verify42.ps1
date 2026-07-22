$ErrorActionPreference = 'Continue'
$cc = 'C:\Users\Smart\Desktop\Claude-Connect'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client'
$upd = Join-Path $repo 'windows\connect-update.ps1'

Write-Output ('REPO_VER=' + (Get-Content (Join-Path $repo 'windows\connect-version.txt') -Raw).Trim())
Write-Output ('CC_VER_BEFORE=' + (Get-Content (Join-Path $cc 'connect-version.txt') -Raw).Trim())

& $upd -ScriptDir $cc -Force 2>&1 | Select-Object -Last 15
Write-Output ('CC_VER_AFTER=' + (Get-Content (Join-Path $cc 'connect-version.txt') -Raw).Trim())

$pairs = @(
  @('windows\connect.ps1', 'connect.ps1'),
  @('windows\connect-update.ps1', 'connect-update.ps1'),
  @('windows\connect-version.txt', 'connect-version.txt'),
  @('git-mode.ps1', 'git-mode.ps1'),
  @('editor-launch.ps1', 'editor-launch.ps1'),
  @('mac\connect.sh', 'mac\connect.sh'),
  @('mac\connect-update.sh', 'mac\connect-update.sh'),
  @('git-mode.sh', 'mac\git-mode.sh'),
  @('editor-launch.sh', 'mac\editor-launch.sh')
)
$bad = @()
foreach ($p in $pairs) {
  $a = Join-Path $repo $p[0]
  $b = Join-Path $cc $p[1]
  if (-not (Test-Path $a)) { $bad += "missing_repo:$($p[0])"; continue }
  if (-not (Test-Path $b)) { $bad += "missing_cc:$($p[1])"; continue }
  if ((Get-FileHash $a).Hash -ne (Get-FileHash $b).Hash) {
    $bad += ("DIFF:" + $p[0] + " vs " + $p[1])
  }
}
if ($bad.Count -eq 0) { 'HASHES_CC_OK' } else { $bad }

$pub = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260721'
if (Test-Path $pub) {
  & $upd -ScriptDir $pub -Force 2>&1 | Select-Object -Last 10
  $pv = Get-ChildItem $pub -Recurse -Filter connect-version.txt | Select-Object -First 1
  if ($pv) { Write-Output ('PUB_VER=' + (Get-Content $pv.FullName -Raw).Trim()) }
}

$sep = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260721\claude-code'
if (Test-Path $sep) {
  & $upd -ScriptDir $sep -Force 2>&1 | Select-Object -Last 10
  $sv = Get-ChildItem $sep -Recurse -Filter connect-version.txt | Select-Object -First 1
  if ($sv) { Write-Output ('SEP_VER=' + (Get-Content $sv.FullName -Raw).Trim()) }
}

# Live checks
. (Join-Path $repo 'editor-launch.ps1')
$cli = Get-RunningCursorProxySocksPort
$settings = Join-Path (Get-CursorRemoteProfileDir) 'User\settings.json'
$sp = $null
if (Test-Path $settings) {
  $j = Get-Content -Raw $settings | ConvertFrom-Json
  if ($j.'http.proxy' -match ':(\d+)') { $sp = [int]$Matches[1] }
}
Write-Output ("LIVE_CLI=$cli LIVE_SETTINGS=$sp MATCH=$([bool]($cli -and $sp -and $cli -eq $sp))")

$ssh = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | Where-Object { $_.CommandLine -match '10808|1908' })
$hasL = @($ssh | Where-Object { $_.CommandLine -match '-L.*10808' }).Count -gt 0
$hasD = @($ssh | Where-Object { $_.CommandLine -match '(^|\s)-D(\s|=)' }).Count -gt 0
$curs = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'")
Write-Output ("TUNNEL_L=$hasL TUNNEL_D=$hasD SSH=$($ssh.Count) CURSOR_PROCS=$($curs.Count)")

$el = Get-Content (Join-Path $repo 'editor-launch.ps1') -Raw
$okPreserve = $el -match 'preserved_open_windows'
$okAlign = $el -match 'Get-RunningCursorProxySocksPort'
Write-Output ("PRESERVE=$okPreserve ALIGN_FN=$okAlign")

$allOk = ($bad.Count -eq 0) -and $okPreserve -and $okAlign -and $hasL -and (-not $hasD) -and ($cli -eq $sp) -and ($curs.Count -ge 1) -and ((Get-Content (Join-Path $cc 'connect-version.txt') -Raw).Trim() -eq '20260721.42')
if ($allOk) { 'COMPLETE_ALL_GREEN' } else { 'COMPLETE_WITH_GAPS' }
