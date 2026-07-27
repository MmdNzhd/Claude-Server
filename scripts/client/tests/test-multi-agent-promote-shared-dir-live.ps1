#Requires -Version 5.1
# test-multi-agent-promote-shared-dir-live.ps1
# MULTI-AGENT LIVE: N parallel Sync-ConnectExeBesideClient against the SAME
# CLAUDE_CONNECT_LAUNCH_DIR + shared last-launch-dir stamp (the race the old
# "isolated stamp per job" tests deliberately avoided).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== MULTI-AGENT LIVE: concurrent promote same launch dir ===' -ForegroundColor White

$updPath = Get-ClientFile 'windows\connect-update.ps1'
$updSrc = Get-Content -LiteralPath $updPath -Raw
$liveExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
if (-not (Test-Path -LiteralPath $liveExe)) {
    foreach ($c in @(
        (Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)),
        (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
    )) { if (Test-Path -LiteralPath $c) { $liveExe = $c; break } }
}
if (-not (Test-Path -LiteralPath $liveExe)) {
    Write-Host '  FAIL  no seed EXE' -ForegroundColor Red
    exit 1
}
$srcHash = (Get-FileHash -LiteralPath $liveExe -Algorithm MD5).Hash

$needed = @(
    'Test-ConnectLaunchDirUsable',
    'Get-ConnectVersionedLayout',
    'Test-IsConnectVersionedSrcDir',
    'Test-IsConnectVersionedRootDir',
    'Get-SafeFileSha256',
    'Copy-ExeAtomicSwap',
    'Get-ConnectExePromoteDirs',
    'Sync-ConnectExeBesideClient'
)
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$chunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
[void]$chunk.AppendLine('function Get-LocalVersion { return ''20990101.99'' }')
foreach ($n in $needed) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        if ($n -eq 'Test-ConnectLaunchDirUsable') {
            [void]$chunk.AppendLine('function Test-ConnectLaunchDirUsable { param([string]$Dir) if(-not $Dir){return $false}; try{[void][IO.Path]::GetFullPath($Dir)}catch{return $false}; return $true }')
            continue
        }
        Assert $false "extract $n"; throw "missing $n"
    }
    [void]$chunk.AppendLine($fn)
}
$helpersText = $chunk.ToString()
# SHARED stamp path across all workers (the point of this test).
$helpersText = $helpersText -replace 'Join-Path \$env:USERPROFILE ''\.config\\claude-connect\\last-launch-dir\.txt''', '$env:CC_MA_SHARED_STAMP'
$helpersText = $helpersText -replace 'Get-CimInstance Win32_Process -Filter "Name LIKE ''Claude-Connect%''" -ErrorAction SilentlyContinue', '@()'

$root = Join-Path $env:TEMP ("cc-ma-promo-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$launch = Join-Path $root 'shared launch'
$install = Join-Path $root 'install'
$stamp = Join-Path $root 'last-launch-dir.txt'
$helpersFile = Join-Path $root 'helpers.ps1'
$worker = Join-Path $root 'promo-worker.ps1'
$null = New-Item -ItemType Directory -Force -Path $launch, $install
Copy-Item -LiteralPath $liveExe -Destination (Join-Path $install 'Claude-Connect.exe') -Force
# Decoy older version that MUST survive concurrent promotes
Copy-Item -LiteralPath $liveExe -Destination (Join-Path $launch 'Claude-Connect-20990101.01.exe') -Force
$decoyHash = (Get-FileHash -LiteralPath (Join-Path $launch 'Claude-Connect-20990101.01.exe') -Algorithm MD5).Hash
Set-Content -LiteralPath $stamp -Value $launch -Encoding ASCII -NoNewline
Set-Content -LiteralPath $helpersFile -Value $helpersText -Encoding UTF8

$workerBody = @'
$ErrorActionPreference = 'Stop'
. $env:CC_MA_HELPERS
$ScriptDir = $env:CC_MA_INSTALL
$env:CLAUDE_CONNECT_LAUNCH_DIR = $env:CC_MA_LAUNCH
$ver = $args[0]
$out = $args[1]
try {
    Sync-ConnectExeBesideClient -VersionLabel $ver
    $p = Join-Path $env:CC_MA_LAUNCH ("Claude-Connect-{0}.exe" -f $ver)
    if (Test-Path -LiteralPath $p) {
        Set-Content -LiteralPath $out -Value ('ok ' + (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash) -Encoding ASCII
        exit 0
    }
    Set-Content -LiteralPath $out -Value 'missing' -Encoding ASCII
    exit 1
} catch {
    Set-Content -LiteralPath $out -Value ('err ' + $_.Exception.Message) -Encoding ASCII
    exit 2
}
'@
Set-Content -LiteralPath $worker -Value $workerBody -Encoding UTF8

$versions = @('20990101.11', '20990101.22', '20990101.33', '20990101.44')
$procs = @()
$outs = @()
try {
    Note 'CaseA: 4 parallel Sync against SAME launch dir + SAME stamp'
    $env:CC_MA_HELPERS = $helpersFile
    $env:CC_MA_INSTALL = $install
    $env:CC_MA_LAUNCH = $launch
    $env:CC_MA_SHARED_STAMP = $stamp

    foreach ($v in $versions) {
        $out = Join-Path $root ("out-$v.txt")
        $outs += $out
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$worker`"", $v, "`"$out`""
        ) -PassThru -WindowStyle Hidden
        $procs += $p
        Start-Sleep -Milliseconds 40
    }

    foreach ($p in $procs) { $null = $p.WaitForExit(60000) }

    foreach ($v in $versions) {
        $exe = Join-Path $launch ("Claude-Connect-{0}.exe" -f $v)
        Assert (Test-Path -LiteralPath $exe) ("CaseA $v EXE exists after parallel Sync")
        if (Test-Path $exe) {
            Assert ((Get-FileHash -LiteralPath $exe -Algorithm MD5).Hash -eq $srcHash) ("CaseA $v md5 matches seed")
        }
        # No leftover temp swap debris next to versioned name
        $tmps = @(Get-ChildItem -LiteralPath $launch -Filter ("Claude-Connect-{0}.exe*" -f $v) -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne ("Claude-Connect-{0}.exe" -f $v) })
        Assert ($tmps.Count -eq 0) ("CaseA $v no .tmp/.swp debris")
    }

    Assert (Test-Path (Join-Path $launch 'Claude-Connect.exe')) 'CaseA bare Claude-Connect.exe present (external dir)'
    $decoy = Join-Path $launch 'Claude-Connect-20990101.01.exe'
    Assert (Test-Path $decoy) 'CaseA decoy older EXE kept'
    Assert ((Get-FileHash -LiteralPath $decoy -Algorithm MD5).Hash -eq $decoyHash) 'CaseA decoy bytes unchanged'

    $stampNow = (Get-Content -LiteralPath $stamp -Raw).Trim()
    Assert ($stampNow -eq ([IO.Path]::GetFullPath($launch)) -or $stampNow -eq $launch) `
        'CaseA shared stamp still a single valid launch path (not corrupted mash)'

    $okOuts = 0
    foreach ($o in $outs) {
        if ((Test-Path $o) -and ((Get-Content $o -Raw) -match '^ok ')) { $okOuts++ }
    }
    Assert ($okOuts -eq $versions.Count) ("CaseA all workers reported ok ($okOuts/$($versions.Count))")

} catch {
    Write-Host ("  FAIL  exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {} }
    }
    Remove-Item Env:CC_MA_HELPERS, Env:CC_MA_INSTALL, Env:CC_MA_LAUNCH, Env:CC_MA_SHARED_STAMP -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("MULTI-AGENT promote-shared RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("MULTI-AGENT promote-shared RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
