#Requires -Version 5.1
# HARDEST LIVE gate for console hide:
# Static contracts + spaced path + paren/unicode edges + parallel/mixed storms
# + conhost sampling + fail-open belt. Allowed visible: connect-boot/connect.ps1 UI only.
$ErrorActionPreference = 'Stop'
$Fail = 0
$Pass = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

$RepoWin = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\windows'))
$RepoPub = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\publish'))
$batProd = Get-Content -LiteralPath (Join-Path $RepoWin 'connect.bat') -Raw
$updRaw = Get-Content -LiteralPath (Join-Path $RepoWin 'connect-update.ps1') -Raw
$bootRaw = Get-Content -LiteralPath (Join-Path $RepoWin 'connect-boot.ps1') -Raw
$hideVbsProd = Get-Content -LiteralPath (Join-Path $RepoWin 'connect-hide-relaunch.vbs') -Raw
$launchBody = ''
$lbPath = Join-Path $RepoPub '_setup-launch-body.ps1'
if (Test-Path -LiteralPath $lbPath) { $launchBody = Get-Content -LiteralPath $lbPath -Raw }

Write-Host '=== HARDEST LIVE: console hide storm ===' -ForegroundColor White
Write-Host '--- Static contract ---' -ForegroundColor Cyan

Assert (Test-Path (Join-Path $RepoWin 'connect-hide-relaunch.vbs')) 'prod ships connect-hide-relaunch.vbs'
Assert (Test-Path (Join-Path $RepoWin 'connect-hide-console.ps1')) 'prod ships connect-hide-console.ps1'
Assert ($batProd -match 'connect-hide-relaunch\.vbs') 'prod connect.bat references hide-relaunch vbs'
Assert ($batProd -match 'connect-hide-console\.ps1') 'prod connect.bat references hide-console ps1'
Assert ($batProd -notmatch '/MIN') 'prod connect.bat has zero /MIN tokens'
Assert ($batProd -match 'wscript\.exe //B //Nologo') 'prod BAT_INNER uses wscript //B //Nologo'
Assert ($hideVbsProd -match ',\s*0,\s*False') 'hide-relaunch.vbs uses WshShell.Run style 0'
Assert ($hideVbsProd -match 'CLAUDE_CONNECT_BAT_INNER') 'hide-relaunch.vbs sets BAT_INNER env'
Assert ($bootRaw -match 'connect-hide-relaunch\.vbs') 'root stub prefers hide-relaunch vbs'
Assert ($bootRaw -notmatch '/MIN') 'connect-boot stub has no /MIN'
Assert ($batProd -match 'connect-hide-console\.ps1" 2>nul') 'prod bat swallows hide-console errors with 2>nul'

$unhidden = @()
$lineNo = 0
foreach ($line in ($batProd -split "`r?`n")) {
    $lineNo++
    if ($line -notmatch '^\s*powershell(\.exe)?\s') { continue }
    if ($line -match 'connect-boot\.ps1') { continue }
    $head = $line
    foreach ($tok in @('-Command', '-File')) {
        $ix = $head.IndexOf($tok)
        if ($ix -ge 0) { $head = $head.Substring(0, $ix); break }
    }
    if ($head -notmatch '-WindowStyle\s+Hidden') { $unhidden += $lineNo }
}
Assert ($unhidden.Count -eq 0) ("prod bat helper powershell all outer-Hidden (bad: $($unhidden -join ','))")
Assert ($batProd -match 'start "" /D "%HERE_NOTRAIL%" powershell\.exe') 'final UI still uses start powershell connect-boot'
$uiLine = ($batProd -split "`r?`n" | Where-Object { $_ -match 'start "" /D .*connect-boot\.ps1' } | Select-Object -First 1)
Assert ($uiLine -and $uiLine -notmatch '-WindowStyle Hidden') 'final UI start is NOT WindowStyle Hidden'
Assert ($updRaw -match 'Start-Process -FilePath \$bat -WorkingDirectory \$ScriptDir -WindowStyle Hidden') 'connect-update bat_relaunch Hidden'
Assert ($updRaw -match "wscript\.exe //B //Nologo `"%~dp0Claude-Connect\.vbs`"") 'instant launcher cmd is direct wscript'
Assert ($updRaw -notmatch '/MIN wscript') 'connect-update has no /MIN wscript'
if ($launchBody) {
    Assert ($launchBody -notmatch '/MIN wscript') 'publish setup-launch has no /MIN wscript'
    Assert ($launchBody -match "wscript\.exe //B //Nologo `"%~dp0Claude-Connect\.vbs`"") 'publish setup-launch direct wscript'
}

Write-Host '--- LIVE sandbox (spaced ASCII path) ---' -ForegroundColor Cyan
$root = Join-Path $env:TEMP ('cc hide STORM hard x-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$src = Join-Path $root 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null

foreach ($n in @('connect.bat', 'connect-hide-relaunch.vbs', 'connect-hide-console.ps1', 'connect-version.txt')) {
    Copy-Item -Force (Join-Path $RepoWin $n) (Join-Path $src $n)
}
$ver = (Get-Content -LiteralPath (Join-Path $src 'connect-version.txt') -Raw).Trim()

@'
param([string]$Here)
$ok = Join-Path $env:TEMP 'claude-connect-preflight.ok'
@('SKIP_UPDATE=1','SKIP_HEAL=1') | Set-Content -LiteralPath $ok -Encoding ASCII
exit 0
'@ | Set-Content -LiteralPath (Join-Path $src 'connect-preflight.ps1') -Encoding ASCII

Set-Content -LiteralPath (Join-Path $src 'connect.ps1') -Value @"
`$script:ConnectVersion = '$ver'
function Choose-Project { }
# @(Choose-Project
function Show-ConnectHygieneInteractive { }
"@ -Encoding ASCII
Set-Content -LiteralPath (Join-Path $src 'connect-ui.ps1') -Value '# H hygiene' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $src 'editor-launch.ps1') -Value '# Path.Combine' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $src 'git-mode.ps1') -Value 'function Acquire-TunnelPort { }' -Encoding ASCII
foreach ($n in @('windows-mcp-laptop.ps1', 'cursor-auth-laptop.ps1', 'connect-diagnostic.ps1', 'cursor-proxy-sidecar.ps1')) {
    Set-Content -LiteralPath (Join-Path $src $n) -Value '#' -Encoding ASCII
}

Set-Content -LiteralPath (Join-Path $src 'connect-boot.ps1') -Value @'
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "boot.marks"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir ("boot-{0}.marker" -f $PID)) -Value ("ok pid={0}" -f $PID) -Encoding ASCII
Set-Content -LiteralPath (Join-Path $root "boot.marker") -Value "1" -Encoding ASCII
Start-Sleep -Milliseconds 350
exit 0
'@ -Encoding ASCII

if ($updRaw -notmatch '(?s)(function Write-ConnectInstantLauncher \{.*?\n\})') { throw 'Write-ConnectInstantLauncher missing' }
$fn = $Matches[1]
$tmpFn = Join-Path $env:TEMP 'cc-instant-fn-hardest.ps1'
Set-Content -LiteralPath $tmpFn -Value $fn -Encoding UTF8
function Write-UpdateFileLog { param($Message, $Level = 'INFO') }
. $tmpFn
Write-ConnectInstantLauncher -VerDir $root -SrcDir $src

Assert (Test-Path (Join-Path $src 'connect-hide-relaunch.vbs')) 'sandbox has hide-relaunch vbs'
Assert (Test-Path (Join-Path $src 'connect-hide-console.ps1')) 'sandbox has hide-console ps1'
Assert ($root -match 'cc hide STORM hard x-') 'sandbox path is adversarially spaced'
$cmdText = Get-Content (Join-Path $root 'Claude-Connect.cmd') -Raw
Assert ($cmdText -notmatch '/MIN') 'Claude-Connect.cmd has no /MIN'
Assert ($cmdText -notmatch 'start\s+') 'Claude-Connect.cmd has no start'
Assert ($cmdText -match 'wscript\.exe //B //Nologo') 'Claude-Connect.cmd calls wscript directly'

$visibleHits = New-Object System.Collections.Generic.List[string]
$step = 25
$rootEsc = [regex]::Escape($root)
$srcEsc = [regex]::Escape($src)

function Test-IsAllowedUi([string]$Name, [string]$Cmd) {
    return ($Name -eq 'powershell' -and $Cmd -match '(?i)connect-boot\.ps1|(?i)[\\/]connect\.ps1(\s|$|")')
}
function Test-IsConnectRelated([string]$Cmd, [string]$Title) {
    if ($Title -match '(?i)Claude Connect') { return $true }
    if ($Cmd -match $rootEsc -or $Cmd -match $srcEsc) { return $true }
    if ($Cmd -match '(?i)Claude-Connect\.(cmd|vbs)|connect\.bat|connect-hide-relaunch|connect-hide-console') { return $true }
    return $false
}
function Sample-VisibleConnectLeak([int[]]$Ignore = @()) {
    Get-Process cmd, powershell, conhost -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -and ($Ignore -notcontains $_.Id)
    } | ForEach-Object {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue
        $cl = if ($cim) { [string]$cim.CommandLine } else { '' }
        $title = [string]$_.MainWindowTitle
        $name = $_.ProcessName
        if ($name -eq 'conhost') {
            $parId = if ($cim) { [int]$cim.ParentProcessId } else { 0 }
            if ($parId -le 0) { return }
            $par = Get-CimInstance Win32_Process -Filter "ProcessId=$parId" -ErrorAction SilentlyContinue
            if (-not $par) { return }
            $pcl = [string]$par.CommandLine
            $pname = [IO.Path]::GetFileNameWithoutExtension([string]$par.Name)
            if (-not (Test-IsConnectRelated $pcl '')) { return }
            if (Test-IsAllowedUi $pname $pcl) { return }
            $script:visibleHits.Add(("conhost pid={0} parent={1}" -f $_.Id, $parId))
            return
        }
        if (-not (Test-IsConnectRelated $cl $title)) { return }
        if (Test-IsAllowedUi $name $cl) { return }
        $script:visibleHits.Add(("{0} pid={1} title=[{2}]" -f $name, $_.Id, $title))
    }
}
function Clear-SandboxProcs {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and ($_.CommandLine -match $srcEsc -or $_.CommandLine -match $rootEsc)
    } | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}
function Wait-And-Sample([int[]]$Ignore = @(), [int]$Ms = 4000) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Ms)
    while ([DateTime]::UtcNow -lt $deadline) {
        Sample-VisibleConnectLeak $Ignore
        Start-Sleep -Milliseconds $step
    }
}
function Clear-BootMarks {
    Remove-Item (Join-Path $root 'boot.marker') -Force -ErrorAction SilentlyContinue
    $d = Join-Path $root 'boot.marks'
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}
function Read-BootCount {
    $d = Join-Path $root 'boot.marks'
    if (Test-Path -LiteralPath $d) {
        return @(Get-ChildItem -LiteralPath $d -Filter 'boot-*.marker' -File -ErrorAction SilentlyContinue).Count
    }
    if (Test-Path -LiteralPath (Join-Path $root 'boot.marker')) { return 1 }
    return 0
}
function Wait-BootMarks([int]$Need, [int]$MaxLoops = 50) {
    $i = 0
    while ((Read-BootCount) -lt $Need -and $i -lt $MaxLoops) { Start-Sleep -Milliseconds 100; $i++ }
}
function Start-OuterBat { return Start-Process -FilePath (Join-Path $src 'connect.bat') -WorkingDirectory $src -PassThru }
function Start-CmdTrampoline {
    Start-Process -FilePath "$env:ComSpec" -ArgumentList @('/d', '/c', ('"{0}"' -f (Join-Path $root 'Claude-Connect.cmd'))) -WindowStyle Hidden | Out-Null
}
function Start-VbsDirect {
    $vbs = Join-Path $root 'Claude-Connect.vbs'
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList ('//B //Nologo "' + $vbs + '"') -WorkingDirectory $root | Out-Null
}
function Dump-Leaks {
    if ($visibleHits.Count -gt 0) {
        $visibleHits | Select-Object -First 8 | ForEach-Object { Write-Host "    leak: $_" -ForegroundColor Yellow }
    }
}

# A
Note 'CaseA: single OUTER bat'
Clear-BootMarks; $visibleHits.Clear()
$p = Start-OuterBat
$ow = 0; while ($p -and -not $p.HasExited -and $ow -lt 120) { Start-Sleep -Milliseconds 40; $ow++ }
Wait-And-Sample @($p.Id) 4500
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 1) ('CaseA boot marks >=1')
Assert ($visibleHits.Count -eq 0) ('CaseA zero visible leaks')
Dump-Leaks

# A2 paren path - VBS only
Note 'CaseA2: paren path - VBS still hide-safe'
$pRoot = Join-Path $env:TEMP ('cc hide STORM hard p-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + ' (x)')
$pSrc = Join-Path $pRoot 'src'
try {
    New-Item -ItemType Directory -Force -Path $pSrc | Out-Null
    foreach ($n in @('connect-version.txt')) { Copy-Item -Force (Join-Path $RepoWin $n) (Join-Path $pSrc $n) }
    Copy-Item -Force (Join-Path $src 'connect-boot.ps1') (Join-Path $pSrc 'connect-boot.ps1')
    Write-ConnectInstantLauncher -VerDir $pRoot -SrcDir $pSrc
    $oldRootEsc = $rootEsc; $oldSrcEsc = $srcEsc
    $rootEsc = [regex]::Escape($pRoot); $srcEsc = [regex]::Escape($pSrc)
    $visibleHits.Clear()
    $vbsP = Join-Path $pRoot 'Claude-Connect.vbs'
    1..3 | ForEach-Object {
        Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList ('//B //Nologo "' + $vbsP + '"') -WorkingDirectory $pRoot | Out-Null
        Start-Sleep -Milliseconds 100
    }
    Wait-And-Sample @() 4500
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match [regex]::Escape($pRoot)
    } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue } catch {} }
    $pc = @(Get-ChildItem -LiteralPath (Join-Path $pRoot 'boot.marks') -Filter 'boot-*.marker' -File -EA SilentlyContinue).Count
    Assert ($pc -ge 3) ('CaseA2 paren-path VBS boot marks >=3')
    Assert ($visibleHits.Count -eq 0) ('CaseA2 paren-path zero visible leaks')
    $rootEsc = $oldRootEsc; $srcEsc = $oldSrcEsc
} finally {
    try { Remove-Item -LiteralPath $pRoot -Recurse -Force -EA SilentlyContinue } catch {}
}

Start-Sleep -Seconds 1
Note 'CaseB: OUTER bat x5 staggered'
Clear-BootMarks; $visibleHits.Clear()
$outers = @(); 1..5 | ForEach-Object { $outers += Start-OuterBat; Start-Sleep -Milliseconds 80 }
Wait-And-Sample @($outers | ForEach-Object { $_.Id }) 6000
Wait-BootMarks 5
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 4) ('CaseB boot marks >=4 after OUTER x5')
Assert ($visibleHits.Count -eq 0) ('CaseB zero visible leaks')
Dump-Leaks

Start-Sleep -Seconds 1
Note 'CaseC: cmd trampoline x6'
Clear-BootMarks; $visibleHits.Clear()
1..6 | ForEach-Object { Start-CmdTrampoline; Start-Sleep -Milliseconds 60 }
Wait-And-Sample @() 6000
Wait-BootMarks 5
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 5) ('CaseC boot marks >=5 after cmd x6')
Assert ($visibleHits.Count -eq 0) ('CaseC zero visible leaks')
Dump-Leaks

Start-Sleep -Seconds 1
Note 'CaseD: VBS direct x3'
Clear-BootMarks; $visibleHits.Clear()
1..3 | ForEach-Object { Start-VbsDirect; Start-Sleep -Milliseconds 120 }
Wait-And-Sample @() 5000
Wait-BootMarks 3
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 3) ('CaseD boot marks >=3 via VBS')
Assert ($visibleHits.Count -eq 0) ('CaseD zero visible leaks')
Dump-Leaks

Start-Sleep -Seconds 1
Note 'CaseE: fallback without hide-relaunch.vbs'
$vbsBak = Join-Path $src 'connect-hide-relaunch.vbs.bak'
Move-Item -Force (Join-Path $src 'connect-hide-relaunch.vbs') $vbsBak
Clear-BootMarks; $visibleHits.Clear()
$p = Start-OuterBat
$ow = 0; while ($p -and -not $p.HasExited -and $ow -lt 120) { Start-Sleep -Milliseconds 40; $ow++ }
Wait-And-Sample @($p.Id) 5000
Wait-BootMarks 1
Clear-SandboxProcs
Move-Item -Force $vbsBak (Join-Path $src 'connect-hide-relaunch.vbs')
Assert ((Read-BootCount) -ge 1) ('CaseE fallback boot marks >=1')
Assert ($visibleHits.Count -eq 0) ('CaseE fallback zero visible leaks')
Dump-Leaks

Note 'CaseF: no visible titled Claude Connect cmd'
Clear-BootMarks
$titled = 0
$p = Start-OuterBat
$ow = 0; while ($p -and -not $p.HasExited -and $ow -lt 120) { Start-Sleep -Milliseconds 40; $ow++ }
$deadline = [DateTime]::UtcNow.AddMilliseconds(3000)
while ([DateTime]::UtcNow -lt $deadline) {
    Get-Process cmd -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Id -ne $p.Id -and $_.MainWindowTitle -match '(?i)Claude Connect'
    } | ForEach-Object { $titled++ }
    Start-Sleep -Milliseconds 25
}
Clear-SandboxProcs
Assert ($titled -eq 0) ('CaseF zero visible titled Claude Connect cmd')

Start-Sleep -Seconds 1
Note 'CaseG: mixed 2 bat + 2 cmd + 2 vbs'
Clear-BootMarks; $visibleHits.Clear()
$mixIgnore = New-Object System.Collections.Generic.List[int]
1..2 | ForEach-Object {
    $op = Start-OuterBat
    if ($op) { $mixIgnore.Add($op.Id) }
    Start-CmdTrampoline
    Start-VbsDirect
    Start-Sleep -Milliseconds 100
}
Wait-And-Sample @($mixIgnore) 7000
Wait-BootMarks 5
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 5) ('CaseG mixed boot marks >=5')
Assert ($visibleHits.Count -eq 0) ('CaseG mixed zero visible leaks')
Dump-Leaks

Start-Sleep -Seconds 1
Note 'CaseH: rapid OUTER x6'
Clear-BootMarks; $visibleHits.Clear()
$burst = @(); 1..6 | ForEach-Object { $burst += Start-OuterBat; Start-Sleep -Milliseconds 80 }
Wait-And-Sample @($burst | ForEach-Object { $_.Id }) 7000
Wait-BootMarks 5
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 5) ('CaseH rapid OUTER boot marks >=5')
Assert ($visibleHits.Count -eq 0) ('CaseH rapid zero visible leaks')
Dump-Leaks

Note 'CaseI: hide-console throws - belt fail-open'
$hcPath = Join-Path $src 'connect-hide-console.ps1'
$hcBak = Join-Path $src 'connect-hide-console.ps1.bak'
Copy-Item -Force $hcPath $hcBak
Set-Content -LiteralPath $hcPath -Value 'throw "hide-console boom"' -Encoding ASCII
Clear-BootMarks; $visibleHits.Clear()
$p = Start-OuterBat
$ow = 0; while ($p -and -not $p.HasExited -and $ow -lt 120) { Start-Sleep -Milliseconds 40; $ow++ }
Wait-And-Sample @($p.Id) 4500
Wait-BootMarks 1
Clear-SandboxProcs
Copy-Item -Force $hcBak $hcPath
Assert ((Read-BootCount) -ge 1) ('CaseI throwing-belt boot marks >=1')
Assert ($visibleHits.Count -eq 0) ('CaseI throwing-belt zero visible leaks')

Note 'CaseJ: root stub to hide-relaunch'
$stubBat = Join-Path $root 'connect.bat'
@(
    '@echo off'
    'if exist "%~dp0src\connect-hide-relaunch.vbs" ('
    '  wscript.exe //B //Nologo "%~dp0src\connect-hide-relaunch.vbs" %*'
    '  exit /b 0'
    ')'
    'exit /b 1'
) | Set-Content -LiteralPath $stubBat -Encoding ASCII
Clear-BootMarks; $visibleHits.Clear()
$p = Start-Process -FilePath $stubBat -WorkingDirectory $root -PassThru
$ow = 0; while ($p -and -not $p.HasExited -and $ow -lt 120) { Start-Sleep -Milliseconds 40; $ow++ }
Wait-And-Sample @($p.Id) 4500
Wait-BootMarks 1
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 1) ('CaseJ root stub boot marks >=1')
Assert ($visibleHits.Count -eq 0) ('CaseJ root stub zero visible leaks')

Start-Sleep -Seconds 1
Note 'CaseK: double-wave mixed'
Clear-BootMarks; $visibleHits.Clear()
$ign2 = New-Object System.Collections.Generic.List[int]
1..2 | ForEach-Object {
    $op = Start-OuterBat; if ($op) { $ign2.Add($op.Id) }
    Start-CmdTrampoline; Start-VbsDirect; Start-Sleep -Milliseconds 80
}
Start-Sleep -Milliseconds 200
1..2 | ForEach-Object {
    $op = Start-OuterBat; if ($op) { $ign2.Add($op.Id) }
    Start-CmdTrampoline; Start-VbsDirect; Start-Sleep -Milliseconds 80
}
Wait-And-Sample @($ign2) 7000
Wait-BootMarks 4
Clear-SandboxProcs
Assert ((Read-BootCount) -ge 4) ('CaseK double-wave boot marks >=4')
Assert ($visibleHits.Count -eq 0) ('CaseK double-wave zero visible leaks')
Dump-Leaks

# CaseU unicode
Note 'CaseU: unicode path VBS+cmd hide-safe'
# Build unicode leaf via char codes (keep this .ps1 ASCII-safe)
$uRoot = Join-Path $env:TEMP (('cc hide U-{0}-' -f [guid]::NewGuid().ToString('N').Substring(0, 6)) + [char]0x0637 + [char]0x0648)
$uSrc = Join-Path $uRoot 'src'
try {
    New-Item -ItemType Directory -Force -Path $uSrc | Out-Null
    Set-Content -LiteralPath (Join-Path $uSrc 'connect-boot.ps1') -Value @'
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "boot.marks"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir ("boot-{0}.marker" -f $PID)) -Value ("ok "+$PID) -Encoding ASCII
Start-Sleep -Milliseconds 300
exit 0
'@ -Encoding ASCII
    Write-ConnectInstantLauncher -VerDir $uRoot -SrcDir $uSrc
    Assert (Test-Path -LiteralPath (Join-Path $uRoot 'Claude-Connect.vbs')) 'CaseU wrote vbs'
    Assert (Test-Path -LiteralPath (Join-Path $uRoot 'Claude-Connect.cmd')) 'CaseU wrote cmd'
    $uHits = New-Object System.Collections.Generic.List[string]
    $savedHits = $visibleHits
    $script:visibleHits = $uHits
    $oldRootEsc = $rootEsc; $oldSrcEsc = $srcEsc
    $rootEsc = [regex]::Escape($uRoot); $srcEsc = [regex]::Escape($uSrc)
    $vbsU = Join-Path $uRoot 'Claude-Connect.vbs'
    $cmdU = Join-Path $uRoot 'Claude-Connect.cmd'
    1..2 | ForEach-Object {
        Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList ('//B //Nologo "' + $vbsU + '"') -WorkingDirectory $uRoot | Out-Null
        Start-Sleep -Milliseconds 120
    }
    1..2 | ForEach-Object {
        Start-Process -FilePath "$env:ComSpec" -ArgumentList @('/d', '/c', ('"{0}"' -f $cmdU)) -WindowStyle Hidden | Out-Null
        Start-Sleep -Milliseconds 80
    }
    Wait-And-Sample @() 5000
    $uCount = @(Get-ChildItem -LiteralPath (Join-Path $uRoot 'boot.marks') -Filter 'boot-*.marker' -File -EA SilentlyContinue).Count
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match [regex]::Escape($uRoot)
    } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue } catch {} }
    Assert ($uCount -ge 1) ('CaseU unicode boot marks >=1')
    Assert ($uHits.Count -eq 0) ('CaseU unicode zero visible leaks')
    $rootEsc = $oldRootEsc; $srcEsc = $oldSrcEsc
    $script:visibleHits = $savedHits
} finally {
    try { Remove-Item -LiteralPath $uRoot -Recurse -Force -EA SilentlyContinue } catch {}
}

try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}

Write-Host ("HARDEST LIVE CONSOLE HIDE STORM: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($Fail -eq 0) { 0 } else { 1 })
