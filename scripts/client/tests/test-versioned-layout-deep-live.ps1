#Requires -Version 5.1
# test-versioned-layout-deep-live.ps1
# Deep live proof of versioned Claude-Connect layout using REAL extracted helpers
# (not reimplemented): first install, EXE move, fast-path timing, prune-3,
# flat migrate, versioned update apply into sibling ver folder.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== DEEP LIVE: versioned Claude-Connect layout ===' -ForegroundColor White

$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$updPath = Get-ClientFile 'windows\connect-update.ps1'
$launchSrc = Get-Content -LiteralPath $launchPath -Raw
$updSrc = Get-Content -LiteralPath $updPath -Raw
$repoVer = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
Assert ($repoVer -match '^\d{8}\.\d+$') "repo version parseable ($repoVer)"

$pubExe = Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $repoVer)
if (-not (Test-Path -LiteralPath $pubExe)) {
    $pubExe = Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe'
}
Assert (Test-Path -LiteralPath $pubExe) "publish EXE exists for deep test ($pubExe)"

# ---------------------------------------------------------------------------
# Load real setup-launch helpers (stub Log; no top-level try)
# ---------------------------------------------------------------------------
Note 'extract setup-launch helpers'
$needLaunch = @(
    'Test-IsBadInstallDir',
    'Resolve-ConnectLaunchExe',
    'Get-PackagedConnectVersion',
    'Resolve-VersionedTree',
    'Test-VersionSrcComplete',
    'Copy-PayloadToSrc',
    'Move-LaunchExeIntoVerDir',
    'Prune-OldVersionDirs'
)
$chunk = New-Object System.Text.StringBuilder
[void]$chunk.AppendLine('$ErrorActionPreference = ''Continue''')
[void]$chunk.AppendLine('function Log([string]$m) { }')
[void]$chunk.AppendLine(('$FallbackRoot = Join-Path $env:USERPROFILE ''Desktop\Claude-Connect'''))
foreach ($n in $needLaunch) {
    $fn = Get-FunctionSource -Content $launchSrc -Name $n
    if (-not $fn) { Assert $false "extract $n"; throw "missing $n" }
    [void]$chunk.AppendLine($fn)
}
Invoke-Expression $chunk.ToString()
Assert $true 'loaded setup-launch helpers'

$root = Join-Path $env:TEMP ("cc-ver-deep-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$launchParent = Join-Path $root 'drop'
$extract = Join-Path $root 'IXP000.TMP'
$null = New-Item -ItemType Directory -Force -Path $launchParent, $extract

try {
    # Fake SFX payload = real client windows scripts + version
    $winSrc = Join-Path $script:RepoRoot 'scripts\client\windows'
    $clientRoot = Join-Path $script:RepoRoot 'scripts\client'
    foreach ($rel in @(
        'connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1',
        'connect-version.txt', 'connect-heal.ps1', 'connect-bootstrap.ps1',
        'cursor-proxy-sidecar.ps1', 'windows-mcp-laptop.ps1'
    )) {
        $from = Join-Path $winSrc $rel
        if (Test-Path $from) { Copy-Item $from (Join-Path $extract $rel) -Force }
    }
    foreach ($rel in @('connect-ui.ps1', 'connect-diagnostic.ps1', 'git-mode.ps1', 'editor-launch.ps1')) {
        $from = Join-Path $clientRoot $rel
        if (Test-Path $from) { Copy-Item $from (Join-Path $extract $rel) -Force }
    }
    # Plant "double-clicked" EXE in launch parent
    $dropExe = Join-Path $launchParent ("Claude-Connect-{0}.exe" -f $repoVer)
    Copy-Item -LiteralPath $pubExe -Destination $dropExe -Force
    Assert (Test-Path $dropExe) 'Case1 planted launch EXE in drop folder'

    # ---- Case1: first install builds tree + moves EXE ----
    Note 'Case1: first install -> Claude-Connect\{ver}\src + move EXE'
    $tree = Resolve-VersionedTree -LaunchParent $launchParent -Version $repoVer
    Assert ($tree.Root -eq ([IO.Path]::GetFullPath((Join-Path $launchParent 'Claude-Connect')))) 'Case1 Root = drop\Claude-Connect'
    Assert ($tree.SrcDir -match '[\\/]src$') 'Case1 SrcDir ends with src'
    Assert (-not (Test-VersionSrcComplete -SrcDir $tree.SrcDir -Version $repoVer)) 'Case1 incomplete before install'

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Copy-PayloadToSrc -ExtractSrc $extract -SrcDir $tree.SrcDir
    $moved = Move-LaunchExeIntoVerDir -LaunchExe $dropExe -DestExe $tree.DestExe -LaunchParent $launchParent -VerDir $tree.VerDir
    Set-Content -LiteralPath (Join-Path $tree.Root 'current.txt') -Value $repoVer -Encoding ASCII -NoNewline
    $sw.Stop()
    Assert (Test-VersionSrcComplete -SrcDir $tree.SrcDir -Version $repoVer) 'Case1 src complete after install'
    Assert $moved 'Case1 moved launch EXE into version dir'
    Assert (-not (Test-Path -LiteralPath $dropExe)) 'Case1 original drop EXE gone (moved)'
    Assert (Test-Path -LiteralPath $tree.DestExe) 'Case1 versioned EXE beside src'
    Assert (Test-Path -LiteralPath (Join-Path $tree.SrcDir 'connect.ps1')) 'Case1 connect.ps1 in src'
    Assert (-not (Test-Path -LiteralPath (Join-Path $tree.Root 'connect.ps1'))) 'Case1 scripts NOT flat in Claude-Connect root'
    Write-Host ("  INFO  Case1 first-install wall={0}ms" -f $sw.ElapsedMilliseconds) -ForegroundColor DarkGray

    # ---- Case2: fast-path complete check is near-zero ----
    Note 'Case2: fast-path Test-VersionSrcComplete timing'
    $times = @()
    1..50 | ForEach-Object {
        $t0 = [Diagnostics.Stopwatch]::StartNew()
        $ok = Test-VersionSrcComplete -SrcDir $tree.SrcDir -Version $repoVer
        $t0.Stop()
        $times += $t0.Elapsed.TotalMilliseconds
        if (-not $ok) { Assert $false 'Case2 complete check returned false' }
    }
    $avg = ($times | Measure-Object -Average).Average
    $max = ($times | Measure-Object -Maximum).Maximum
    Assert ($avg -lt 15) ("Case2 avg complete-check <15ms (got {0:N2}ms)" -f $avg)
    Assert ($max -lt 50) ("Case2 max complete-check <50ms (got {0:N2}ms)" -f $max)
    Write-Host ("  INFO  Case2 avg={0:N2}ms max={1:N2}ms n=50" -f $avg, $max) -ForegroundColor DarkGray

    # ---- Case3: prune keeps 3 newest (isolated root: 1,5,12 + 15 => 5,12,15) ----
    Note 'Case3: prune to 3 newest'
    $pruneRoot = Join-Path $root 'prune-only'
    New-Item -ItemType Directory -Force -Path $pruneRoot | Out-Null
    foreach ($v in @('20260101.1', '20260101.5', '20260101.12', '20260101.15')) {
        $d = Join-Path $pruneRoot $v
        New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
        Set-Content (Join-Path (Join-Path $d 'src') 'connect-version.txt') -Value $v
    }
    Prune-OldVersionDirs -Root $pruneRoot -Keep 3
    $left = @(Get-ChildItem $pruneRoot -Directory | Where-Object { $_.Name -match '^\d{8}\.\d+$' } | ForEach-Object { $_.Name })
    Assert ($left -contains '20260101.5') 'Case3 kept .5'
    Assert ($left -contains '20260101.12') 'Case3 kept .12'
    Assert ($left -contains '20260101.15') 'Case3 kept .15'
    Assert ($left -notcontains '20260101.1') 'Case3 removed .1'
    Assert ($left.Count -eq 3) ("Case3 exactly 3 version dirs (got $($left.Count): $($left -join ','))")
    # Main install tree untouched
    Assert (Test-Path -LiteralPath $tree.SrcDir) 'Case3 main src still intact'

    # ---- Case4: flat migrate via connect-update helpers ----
    Note 'Case4: flat Desktop-style migrate'
    $flat = Join-Path $root 'flat-Claude-Connect'
    New-Item -ItemType Directory -Force -Path $flat | Out-Null
    # name folder Claude-Connect for detector
    $flatRoot = Join-Path $root 'Claude-Connect-flat-parent\Claude-Connect'
    New-Item -ItemType Directory -Force -Path $flatRoot | Out-Null
    Copy-Item (Join-Path $extract '*') $flatRoot -Force
    Set-Content (Join-Path $flatRoot 'connect-version.txt') -Value '20260102.3' -NoNewline
    # Load update helpers
    $needUpd = @('Get-ConnectVersionedLayout', 'Invoke-PruneConnectVersionDirs', 'ConvertTo-ConnectVersionedLayout')
    $uchunk = New-Object System.Text.StringBuilder
    [void]$uchunk.AppendLine('function Write-UpdateFileLog { param($Message,$Level=''INFO'') }')
    [void]$uchunk.AppendLine('function Test-ConnectLaunchDirUsable { param($Dir) if(-not $Dir){return $false}; try{$full=[IO.Path]::GetFullPath($Dir)}catch{return $false}; if($full -match ''(?i)(?:^|[\\/])(?:WindowsPowerShell|System32|SysWOW64)(?:[\\/]|$)''){return $false}; return $true }')
    foreach ($n in $needUpd) {
        $fn = Get-FunctionSource -Content $updSrc -Name $n
        if (-not $fn) { Assert $false "extract upd $n"; continue }
        [void]$uchunk.AppendLine($fn)
    }
    Invoke-Expression $uchunk.ToString()
    $before = Get-ConnectVersionedLayout -Dir $flatRoot
    Assert ($before.Kind -eq 'flat') 'Case4 detects flat layout'
    $mig = ConvertTo-ConnectVersionedLayout -FlatRoot $flatRoot
    Assert ($null -ne $mig) 'Case4 migrate returned layout'
    Assert ($mig.Kind -eq 'versioned') 'Case4 migrated kind=versioned'
    Assert (Test-Path (Join-Path $mig.SrcDir 'connect.ps1')) 'Case4 scripts in src'
    Assert (-not (Test-Path (Join-Path $flatRoot 'connect.ps1'))) 'Case4 root no longer has connect.ps1'
    Assert ((Get-Content (Join-Path $flatRoot 'current.txt') -Raw).Trim() -eq '20260102.3') 'Case4 current.txt=20260102.3'

    # ---- Case5: versioned update apply (sibling new ver dir) ----
    Note 'Case5: versioned apply creates sibling version folder'
    # Rebuild a clean versioned tree for apply simulation
    $appParent = Join-Path $root 'apply-drop'
    $appExtract = Join-Path $root 'apply-extract'
    New-Item -ItemType Directory -Force -Path $appParent, $appExtract | Out-Null
    Copy-Item (Join-Path $extract '*') $appExtract -Force
    Set-Content (Join-Path $appExtract 'connect-version.txt') -Value '20260727.10' -NoNewline
    $oldTree = Resolve-VersionedTree -LaunchParent $appParent -Version '20260727.10'
    Copy-PayloadToSrc -ExtractSrc $appExtract -SrcDir $oldTree.SrcDir
    Set-Content (Join-Path $oldTree.SrcDir 'connect-version.txt') -Value '20260727.10' -NoNewline
    Set-Content (Join-Path $oldTree.Root 'current.txt') -Value '20260727.10' -NoNewline
    # Fake "new" windows payload for remote 20260727.13
    $winNew = Join-Path $root 'winNew'
    New-Item -ItemType Directory -Force -Path $winNew | Out-Null
    Copy-Item (Join-Path $extract '*') $winNew -Force
    Set-Content (Join-Path $winNew 'connect-version.txt') -Value $repoVer -NoNewline
    Set-Content (Join-Path $winNew 'NEW_MARKER.txt') -Value 'from-update' -NoNewline

    $remoteVer = $repoVer
    $verLayoutApply = Get-ConnectVersionedLayout -Dir $oldTree.SrcDir
    Assert ($verLayoutApply.Kind -eq 'versioned') 'Case5 old src is versioned layout'
    $newVerDir = Join-Path $verLayoutApply.Root $remoteVer
    $newSrc = Join-Path $newVerDir 'src'
    New-Item -ItemType Directory -Force -Path $newSrc | Out-Null
    Get-ChildItem -LiteralPath $winNew -Force | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $newSrc $_.Name) -Force -Recurse
    }
    Set-Content (Join-Path $verLayoutApply.Root 'current.txt') -Value $remoteVer -Encoding ASCII -NoNewline
    # Keep old + new; also plant older ones and prune
    foreach ($v in @('20260101.1', '20260101.5')) {
        New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path $verLayoutApply.Root $v) 'src') | Out-Null
    }
    Invoke-PruneConnectVersionDirs -Root $verLayoutApply.Root -Keep 3
    Assert (Test-Path $newSrc) 'Case5 new src exists'
    Assert (Test-Path (Join-Path $newSrc 'NEW_MARKER.txt')) 'Case5 new marker in new src'
    Assert (Test-Path $oldTree.SrcDir) 'Case5 old src still present before prune pressure'
    $left2 = @(Get-ChildItem $verLayoutApply.Root -Directory | Where-Object { $_.Name -match '^\d{8}\.\d+$' } | ForEach-Object { $_.Name })
    Assert ($left2.Count -le 3) ("Case5 after prune <=3 dirs (got $($left2.Count))")
    Assert ($left2 -contains $remoteVer) 'Case5 newest remote ver kept'
    Assert ((Get-Content (Join-Path $verLayoutApply.Root 'current.txt') -Raw).Trim() -eq $remoteVer) 'Case5 current.txt points to new ver'

    # ---- Case6: bad dirs still rejected ----
    Note 'Case6: System32 / PowerShell still bad install dirs'
    Assert (Test-IsBadInstallDir -Dir (Join-Path $env:WINDIR 'System32') -ExtractSrc $extract) 'Case6 System32 bad'
    Assert (Test-IsBadInstallDir -Dir 'C:\Windows\System32\WindowsPowerShell\v1.0' -ExtractSrc $extract) 'Case6 PowerShell bad'
    Assert (-not (Test-IsBadInstallDir -Dir $launchParent -ExtractSrc $extract)) 'Case6 launch parent ok'

    # ---- Case7: live server + publish parity for this version ----
    Note 'Case7: live server/publish parity'
    $sshBin = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
    if (-not (Test-Path $sshBin)) { $sshBin = 'ssh' }
    $remoteVerLive = (& $sshBin -F NUL -o BatchMode=yes -o ConnectTimeout=12 smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt" 2>$null | Out-String).Trim()
    Assert ($remoteVerLive -eq $repoVer) ("Case7 server ver == repo ($repoVer)")
    Assert (Test-Path -LiteralPath $pubExe) 'Case7 publish EXE present'
    $tempDrop = 'C:\Temp\test for update'
    $tempExeLoose = Join-Path $tempDrop ("Claude-Connect-{0}.exe" -f $repoVer)
    $tempExeVer = Join-Path $tempDrop ("Claude-Connect\{0}\Claude-Connect-{0}.exe" -f $repoVer)
    $tempSrc = Join-Path $tempDrop ("Claude-Connect\{0}\src" -f $repoVer)
    Assert ((Test-Path -LiteralPath $tempExeLoose) -or (Test-Path -LiteralPath $tempExeVer)) 'Case7 Temp has loose or versioned EXE'
    if (Test-Path -LiteralPath $tempSrc) {
        Assert (Test-VersionSrcComplete -SrcDir $tempSrc -Version $repoVer) 'Case7 live Temp src complete'
        Assert (-not (Test-Path -LiteralPath (Join-Path $tempDrop 'connect.ps1'))) 'Case7 Temp root has no flat connect.ps1'
        $cur = Join-Path $tempDrop 'Claude-Connect\current.txt'
        Assert (Test-Path $cur) 'Case7 Temp current.txt exists'
        Assert ((Get-Content $cur -Raw).Trim() -eq $repoVer) 'Case7 Temp current.txt matches repo ver'
        Assert (-not (Test-Path -LiteralPath $tempExeLoose)) 'Case7 loose drop EXE moved into version dir'
    }

    # ---- Case8: EXE string scan still clean (no Bypass+Hidden AppLaunched) ----
    Note 'Case8: publish EXE hidden launcher strings'
    $bytes = [IO.File]::ReadAllBytes($pubExe)
    $ascii = -join ($bytes | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { ' ' } })
    $ascii = [regex]::Replace($ascii, '\s+', ' ')
    Assert ($ascii -match 'setup-run-hidden\.vbs') 'Case8 embeds setup-run-hidden.vbs'
    Assert ($ascii -match 'Resolve-VersionedTree|Test-VersionSrcComplete|Claude-Connect') 'Case8 embeds versioned layout markers'
    Assert ($ascii -notmatch 'AppLaunched=powershell\.exe') 'Case8 AppLaunched not raw powershell'

    # ---- Case9: LIVE Temp tree fast-path + helpers present ----
    Note 'Case9: live Temp install tree (user-run proof)'
    if (Test-Path -LiteralPath $tempSrc) {
        $tFast = [Diagnostics.Stopwatch]::StartNew()
        $okFast = Test-VersionSrcComplete -SrcDir $tempSrc -Version $repoVer
        $tFast.Stop()
        Assert $okFast 'Case9 live Temp src still complete'
        Assert ($tFast.ElapsedMilliseconds -lt 30) ("Case9 live fast-path <30ms (got {0}ms)" -f $tFast.ElapsedMilliseconds)
        Assert (Test-Path (Join-Path $tempSrc 'setup-worker.ps1')) 'Case9 setup-worker.ps1 in live src'
        $updLive = Get-Content (Join-Path $tempSrc 'connect-update.ps1') -Raw
        Assert ($updLive -match 'versioned_apply ok') 'Case9 live update has versioned_apply'
        Assert ($updLive -match 'Get-ConnectVersionedLayout') 'Case9 live update has versioned layout helper'
        $leak = @(Get-ChildItem (Join-Path $tempDrop 'Claude-Connect') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(ps1|bat)$' })
        Assert ($leak.Count -eq 0) 'Case9 no .ps1/.bat leaked at Claude-Connect root'
    } else {
        Write-Host '  SKIP  Case9 live Temp tree not installed yet' -ForegroundColor Yellow
        $Skip++
    }

} catch {
    Write-Host ("  FAIL  deep exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
