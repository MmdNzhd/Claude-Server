#Requires -Version 5.1
# test-cursor-profile-migrate-hard.ps1
# HARD live: Ensure-CursorRemoteProfileMigrated in isolated LOCALAPPDATA (never touches real profiles).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARD: Cursor profile migrate (isolated LOCALAPPDATA) ===' -ForegroundColor Cyan
Write-Host ''

$elPath = Get-ClientFile 'editor-launch.ps1'
$elSrc = Get-Content -LiteralPath $elPath -Raw

# Source contracts (ship gates)
Assert ($elSrc -match 'function Ensure-CursorRemoteProfileMigrated') 'Ensure-CursorRemoteProfileMigrated defined'
Assert ($elSrc -match 'Personal Cursor \(%APPDATA%\\Cursor\) is never touched') 'documents personal Cursor untouched'
Assert ($elSrc -match 'Ensure-CursorRemoteProfileMigrated') 'Get-CursorRemoteProfileDir invokes Ensure'
Assert ($elSrc -match '\.claude-connect-profile-migrated') 'stamp file name present'
Assert ($elSrc -match 'ClaudeServerCursorProfile\.bak-keep-') 'legacy archive bak-keep naming'
Assert ($elSrc -match 'bak-pre-migrate-') 'tiny-target backup naming'
Assert ($elSrc -match 'CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE') 'skip env honored'
Assert ($elSrc -notmatch '%APPDATA%\\Cursor.*Rename-Item|Rename-Item.*%APPDATA%\\Cursor') 'migrate does not rename personal APPDATA Cursor'

# Load real functions into this process
. $elPath

$root = Join-Path $env:TEMP ("cc-profile-migrate-hard-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$oldLocal = $env:LOCALAPPDATA
$oldSkip = $env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE
$env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE = $null

function Reset-MigrateFlags {
    $script:CursorProfileMigrateChecked = $false
}

function New-FakeProfileTree([string]$Base, [int]$ApproxKb) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Base 'User\globalStorage') | Out-Null
    $db = Join-Path $Base 'User\globalStorage\state.vscdb'
    $bytes = New-Object byte[] ($ApproxKb * 1024)
    [IO.File]::WriteAllBytes($db, $bytes)
    Set-Content -LiteralPath (Join-Path $Base 'marker.txt') -Value ("size_kb={0}" -f $ApproxKb) -Encoding ASCII
}

try {
    # --- A: no legacy ---
    $env:LOCALAPPDATA = Join-Path $root 'A'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    $dir = Get-CursorRemoteProfileDir
    Assert ($dir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart')) 'A: returns -Smart path'
    Assert (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'))) 'A: no legacy created'
    Assert (-not (Test-Path (Join-Path $dir '.claude-connect-profile-migrated'))) 'A: no stamp when nothing to migrate'

    # --- B: legacy only -> rename to Smart ---
    $env:LOCALAPPDATA = Join-Path $root 'B'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $legacy -ApproxKb 6000
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    $dir = Get-CursorRemoteProfileDir
    Assert ($dir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart')) 'B: target is -Smart'
    Assert (-not (Test-Path -LiteralPath $legacy)) 'B: legacy removed after rename'
    Assert (Test-Path -LiteralPath $dir) 'B: -Smart exists'
    Assert (Test-Path (Join-Path $dir '.claude-connect-profile-migrated')) 'B: stamp written'
    Assert (Test-Path (Join-Path $dir 'User\globalStorage\state.vscdb')) 'B: state.vscdb preserved'

    # --- C: stamp present + leftover legacy => NO-OP (mid-work safety) ---
    $env:LOCALAPPDATA = Join-Path $root 'C'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $smart = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart'
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $smart -ApproxKb 8000
    New-Item -ItemType Directory -Force -Path $smart | Out-Null
    Set-Content -LiteralPath (Join-Path $smart '.claude-connect-profile-migrated') -Value 'ts=already' -Encoding ASCII
    New-FakeProfileTree -Base $legacy -ApproxKb 1000
    $markerBefore = Get-Content (Join-Path $smart 'marker.txt') -Raw
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    [void](Get-CursorRemoteProfileDir)
    Assert (Test-Path -LiteralPath $legacy) 'C: stamp+legacy => legacy NOT touched (no mid-work kill/rename)'
    Assert ((Get-Content (Join-Path $smart 'marker.txt') -Raw) -eq $markerBefore) 'C: stamped smart unchanged'

    # --- D: tiny smart + large legacy => migrate, bak tiny ---
    $env:LOCALAPPDATA = Join-Path $root 'D'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $smart = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart'
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $smart -ApproxKb 200
    New-FakeProfileTree -Base $legacy -ApproxKb 9000
    Set-Content -LiteralPath (Join-Path $legacy 'marker.txt') -Value 'from_legacy' -Encoding ASCII
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    $dir = Get-CursorRemoteProfileDir
    Assert (-not (Test-Path -LiteralPath $legacy)) 'D: legacy gone after migrate'
    Assert ((Get-Content (Join-Path $dir 'marker.txt') -Raw).Trim() -eq 'from_legacy') 'D: large legacy content won'
    Assert (Test-Path (Join-Path $dir '.claude-connect-profile-migrated')) 'D: stamp after migrate'
    $baks = @(Get-ChildItem $env:LOCALAPPDATA -Directory | Where-Object { $_.Name -like 'ClaudeServerCursorProfile-Smart.bak-pre-migrate-*' })
    Assert ($baks.Count -ge 1) 'D: tiny smart backed up as bak-pre-migrate-*'

    # --- E: target larger than legacy => keep target, archive legacy ---
    $env:LOCALAPPDATA = Join-Path $root 'E'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $smart = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart'
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $smart -ApproxKb 9000
    Set-Content -LiteralPath (Join-Path $smart 'marker.txt') -Value 'keep_smart' -Encoding ASCII
    New-FakeProfileTree -Base $legacy -ApproxKb 1000
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    $dir = Get-CursorRemoteProfileDir
    Assert ((Get-Content (Join-Path $dir 'marker.txt') -Raw).Trim() -eq 'keep_smart') 'E: larger smart kept'
    Assert (-not (Test-Path -LiteralPath $legacy)) 'E: legacy archived away'
    $keepBaks = @(Get-ChildItem $env:LOCALAPPDATA -Directory | Where-Object { $_.Name -like 'ClaudeServerCursorProfile.bak-keep-*' })
    Assert ($keepBaks.Count -ge 1) 'E: legacy archived as bak-keep-*'
    Assert (Test-Path (Join-Path $dir '.claude-connect-profile-migrated')) 'E: stamp written'

    # --- F: Sepidz site ---
    $env:LOCALAPPDATA = Join-Path $root 'F'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $legacy -ApproxKb 6000
    $script:CursorProfileSite = 'Sepidz'
    Reset-MigrateFlags
    $dir = Get-CursorRemoteProfileDir
    Assert ($dir -eq (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Sepidz')) 'F: migrates to -Sepidz'
    Assert (-not (Test-Path -LiteralPath $legacy)) 'F: legacy gone'
    Assert (Test-Path (Join-Path $dir '.claude-connect-profile-migrated')) 'F: Sepidz stamp'

    # --- G: skip env ---
    $env:LOCALAPPDATA = Join-Path $root 'G'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $legacy -ApproxKb 6000
    $env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE = '1'
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    [void](Get-CursorRemoteProfileDir)
    Assert (Test-Path -LiteralPath $legacy) 'G: SKIP env leaves legacy in place'
    $env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE = $null

    # --- H: second Get call does not re-migrate (script flag) ---
    $env:LOCALAPPDATA = Join-Path $root 'H'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    New-FakeProfileTree -Base $legacy -ApproxKb 6000
    $script:CursorProfileSite = 'Smart'
    Reset-MigrateFlags
    [void](Get-CursorRemoteProfileDir)
    $stamp1 = Get-Content (Join-Path (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart') '.claude-connect-profile-migrated') -Raw
    # Recreate legacy after migrate to simulate weird leftover; flag should block re-entry this process
    New-FakeProfileTree -Base $legacy -ApproxKb 500
    [void](Get-CursorRemoteProfileDir)
    Assert (Test-Path -LiteralPath $legacy) 'H: same-process second call does not re-enter migrate'
    $stamp2 = Get-Content (Join-Path (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart') '.claude-connect-profile-migrated') -Raw
    Assert ($stamp1 -eq $stamp2) 'H: stamp unchanged on second call'

    # --- I: sidecar fallback must not use bare unsuffixed path ---
    $side = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
    Assert ($side -match 'ClaudeServerCursorProfile-Smart') 'I: sidecar references -Smart'
    # Source: Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart'
    $smartNeedle = "Join-Path " + '$env:LOCALAPPDATA' + " 'ClaudeServerCursorProfile-Smart'"
    Assert ($side.Contains($smartNeedle)) 'I: Get-CursorProxySettingsPath else uses -Smart'
    $bareNeedle = "Join-Path " + '$env:LOCALAPPDATA' + " 'ClaudeServerCursorProfile'"
    Assert (-not $side.Contains($bareNeedle)) 'I: no Join-Path bare ClaudeServerCursorProfile fallback'

    # --- J: versions / policy aligned ---
    $ver = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
    $macVer = (Get-Content (Get-ClientFile 'mac\connect-version.txt') -Raw).Trim()
    $winPs = Select-String -Path (Get-ClientFile 'windows\connect.ps1') -Pattern "ConnectVersion = '([^']+)'" | Select-Object -First 1
    $macSh = Select-String -Path (Get-ClientFile 'mac\connect.sh') -Pattern "CONNECT_VERSION='([^']+)'" | Select-Object -First 1
    $policy = Get-Content (Join-Path $RepoRoot 'scripts\server\client-update-policy.json') -Raw | ConvertFrom-Json
    Assert ($ver -match '^\d{8}\.\d+$') ("J: windows connect-version.txt parseable ($ver)")
    Assert ($macVer -eq $ver) 'J: mac connect-version.txt matches'
    Assert ($winPs.Matches[0].Groups[1].Value -eq $ver) 'J: connect.ps1 ConnectVersion matches'
    Assert ($macSh.Matches[0].Groups[1].Value -eq $ver) 'J: connect.sh CONNECT_VERSION matches'
    Assert ([string]$policy.latest -eq $ver) 'J: client-update-policy.json latest matches'

    # --- K: Mac ensure function ships ---
    $macEl = Get-Content (Get-ClientFile 'editor-launch.sh') -Raw
    Assert ($macEl -match 'ensure_cursor_remote_profile_migrated\(\)') 'K: mac ensure function present'
    $gIdx = $macEl.IndexOf('get_cursor_server_profile_dir()')
    $eIdx = $macEl.IndexOf('ensure_cursor_remote_profile_migrated')
    $callInGet = $false
    if ($gIdx -ge 0) {
        $chunk = $macEl.Substring($gIdx, [Math]::Min(250, $macEl.Length - $gIdx))
        $callInGet = $chunk -match 'ensure_cursor_remote_profile_migrated'
    }
    Assert (($eIdx -ge 0) -and $callInGet) 'K: mac get_cursor_server_profile_dir calls ensure'
}
finally {
    $env:LOCALAPPDATA = $oldLocal
    if ($null -eq $oldSkip) { Remove-Item Env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE -ErrorAction SilentlyContinue }
    else { $env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE = $oldSkip }
    $script:CursorProfileSite = $null
    $script:CursorProfileMigrateChecked = $false
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
Write-Host ("Passed: {0}  Failed: {1}" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
Write-Host 'HARD profile-migrate: ALL PASS' -ForegroundColor Green
exit 0
