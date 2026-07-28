#Requires -Version 5.1
# test-exe-preboot-update-live.ps1
# HARD live: spaced portable folder must boot WITHOUT auto-update (manual menu u only).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: EXE boot without preboot auto-update (manual_only) ==='
Write-Host ''

$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
Assert ($repoVer -match '^\d{8}\.\d+$') "repo ver parseable ($repoVer)"

$workerSrc = Get-Content (Join-Path $script:RepoRoot 'publish\_setup-worker-body.ps1') -Raw
Assert ($workerSrc -match 'preboot update skipped reason=manual_only') 'worker body skips preboot (manual_only)'
Assert ($workerSrc -notmatch 'CLAUDE_CONNECT_UPDATE_YES\s*=\s*''1''') 'worker body does not set UPDATE_YES'

$pubExe = Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)
if (-not (Test-Path -LiteralPath $pubExe)) {
    Write-Host "  SKIP  publish EXE missing: $pubExe" -ForegroundColor Yellow
    $Skip++
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip)
    exit 0
}

$drop = Join-Path $env:TEMP ('my anoterh hard ' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $drop | Out-Null
$launchExe = Join-Path $drop ("Claude-Connect-{0}.exe" -f $repoVer)
Copy-Item -LiteralPath $pubExe -Destination $launchExe -Force
Unblock-File -LiteralPath $launchExe -ErrorAction SilentlyContinue
Note ("drop=$drop")

$marker = 'PREBOOT_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$log = Join-Path $env:TEMP 'claude-connect-setup.log'

cmd /c "set CLAUDE_CONNECT_SETUP_NO_LAUNCH=& set CLAUDE_CONNECT_SETUP_NO_UPDATE=& set CLAUDE_CONNECT_RUN_ID=$marker& start `"`" `"$launchExe`""

$deadline = (Get-Date).AddSeconds(90)
$sawWorker = $false
$sawSkip = $false
$sawBoot = $false
$sawWorkerOk = $false
$sawAutoUpdate = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path -LiteralPath $log)) { continue }
    $tail = @(Get-Content -LiteralPath $log -Tail 100 -ErrorAction SilentlyContinue)
    $blob = ($tail -join "`n")
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'worker begin') { $sawWorker = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'preboot update skipped reason=manual_only') { $sawSkip = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'preboot update begin') { $sawAutoUpdate = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'UPDATE_EXIT exit=') { $sawAutoUpdate = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'connect-boot started') { $sawBoot = $true }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'worker ok') {
        $sawWorkerOk = $true
        break
    }
    if ($blob -match [regex]::Escape($marker) -and $blob -match 'SETUP_WORKER_FAIL') { break }
}
Assert $sawWorkerOk 'worker ok before cleanup'
Assert $sawWorker 'worker began for spaced hard-drop'
Assert $sawSkip 'preboot update skipped (manual_only)'
Assert (-not $sawAutoUpdate) 'no preboot UPDATE_EXIT / begin (no auto-update)'
Assert $sawBoot 'connect-boot started without auto-update'

$root = Join-Path $drop 'Claude-Connect'
$curFile = Join-Path $root 'current.txt'
Assert (Test-Path -LiteralPath $curFile) 'versioned Claude-Connect/current.txt exists'
$cur = if (Test-Path $curFile) { (Get-Content $curFile -Raw).Trim() } else { '' }
Assert ($cur -eq $repoVer) ("current.txt == repo ver ($cur vs $repoVer)")
Assert (-not (Test-Path -LiteralPath $launchExe)) 'original drop EXE moved into version dir'

# Case B: UPDATE_YES still honored by connect-update when automation sets it explicitly
Note 'CaseB: connect-update still honors explicit UPDATE_YES for automation'
$updSrc = Get-Content (Join-Path $script:RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
Assert ($updSrc -match '\$autoYes = \(\$env:CLAUDE_CONNECT_UPDATE_YES -eq ''1''\)') 'autoYes gate in connect-update'
Assert ($updSrc -match 'if \(\$script:Quiet -and -not \$autoYes\)') 'Quiet skip only without UPDATE_YES'

try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$drop*" -and $_.CommandLine -match 'connect-' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }
try { Remove-Item -LiteralPath $drop -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip)
if ($Fail -gt 0) { exit 1 }
exit 0
