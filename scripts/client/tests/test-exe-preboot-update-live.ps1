#Requires -Version 5.1
# test-exe-preboot-update-live.ps1
# HARD live: spaced portable folder + stale local ver must preboot-update to server
# with UPDATE_YES (progress UI path), then boot from current src — not stay on .13.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: EXE preboot update (spaced folder, stale -> server) ==='
Write-Host ''

$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
Assert ($repoVer -match '^\d{8}\.\d+$') "repo ver parseable ($repoVer)"

$pubExe = Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)
if (-not (Test-Path -LiteralPath $pubExe)) {
    Write-Host "  SKIP  publish EXE missing: $pubExe" -ForegroundColor Yellow
    $Skip++
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip)
    exit 0
}

# Spaced folder (user repro: my anoterh test)
$drop = Join-Path $env:TEMP ('my anoterh hard ' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $drop | Out-Null
$launchExe = Join-Path $drop ("Claude-Connect-{0}.exe" -f $repoVer)
Copy-Item -LiteralPath $pubExe -Destination $launchExe -Force
Unblock-File -LiteralPath $launchExe -ErrorAction SilentlyContinue
Note ("drop=$drop")

$marker = 'PREBOOT_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$log = Join-Path $env:TEMP 'claude-connect-setup.log'

# Launch EXE: no install MessageBox (automation), allow update+boot
cmd /c "set CLAUDE_CONNECT_SETUP_NO_LAUNCH=& set CLAUDE_CONNECT_SETUP_NO_UPDATE=& set CLAUDE_CONNECT_RUN_ID=$marker& start `"`" `"$launchExe`""

$deadline = (Get-Date).AddSeconds(90)
$sawWorker = $false
$sawUpdate = $false
$sawBoot = $false
$sawWorkerOk = $false
$postDest = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path -LiteralPath $log)) { continue }
    $tail = @(Get-Content -LiteralPath $log -Tail 100 -ErrorAction SilentlyContinue)
    $blob = ($tail -join "`n")
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'worker begin') { $sawWorker = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'preboot update begin') { $sawUpdate = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'UPDATE_EXIT exit=') { $sawUpdate = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'connect-boot started') {
        $sawBoot = $true
        $bootLine = $tail | Where-Object { $_ -match 'connect-boot started pid=' } | Select-Object -Last 1
        if ($bootLine -match 'dir=(.+)$') { $postDest = $Matches[1].Trim() }
    }
    # Wait for worker ok so cleanup does not delete the tree mid-update (MessageBox race).
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'worker ok') {
        $sawWorkerOk = $true
        break
    }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'SETUP_WORKER_FAIL') { break }
}
Assert $sawWorkerOk 'worker ok before cleanup (no mid-update delete race)'

Assert $sawWorker 'worker began for spaced hard-drop'
Assert $sawUpdate 'preboot update ran (UPDATE_EXIT / begin)'
Assert $sawBoot 'connect-boot started after preboot update'

$root = Join-Path $drop 'Claude-Connect'
$curFile = Join-Path $root 'current.txt'
Assert (Test-Path -LiteralPath $curFile) 'versioned Claude-Connect/current.txt exists'
$cur = if (Test-Path $curFile) { (Get-Content $curFile -Raw).Trim() } else { '' }
Assert ($cur -eq $repoVer) ("current.txt == repo ver ($cur vs $repoVer)")
$srcVer = Join-Path (Join-Path (Join-Path $root $cur) 'src') 'connect-version.txt'
Assert (Test-Path -LiteralPath $srcVer) 'src connect-version.txt exists'
$liveVer = if (Test-Path $srcVer) { (Get-Content $srcVer -Raw).Trim() } else { '' }
Assert ($liveVer -eq $repoVer) ("live src version == repo ($liveVer)")
Assert (-not (Test-Path -LiteralPath $launchExe)) 'original drop EXE moved into version dir'
$verExe = Join-Path (Join-Path $root $cur) ("Claude-Connect-{0}.exe" -f $cur)
Assert (Test-Path -LiteralPath $verExe) 'versioned EXE present beside src'

# Case B: stale src version must bump via Quiet+UPDATE_YES (unit of the Quiet fix)
Note 'CaseB: Quiet+UPDATE_YES applies when local < remote (contract extract)'
$updSrc = Get-Content (Join-Path $script:RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
Assert ($updSrc -match '\$autoYes = \(\$env:CLAUDE_CONNECT_UPDATE_YES -eq ''1''\)') 'autoYes gate in connect-update'
Assert ($updSrc -match 'if \(\$script:Quiet -and -not \$autoYes\)') 'Quiet skip only without UPDATE_YES'

# Cleanup UI from this test (best effort)
try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$drop*" -and $_.CommandLine -match 'connect-' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }
try { Remove-Item -LiteralPath $drop -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("RESULT: {0} pass / 0 fail / {1} skip" -f $Pass, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
