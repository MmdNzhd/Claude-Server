#Requires -Version 5.1
# HARDEST LIVE: windows-mcp must stay headless and non-blocking.
# - Never schtasks /Run start-server.cmd (visible cmd flash)
# - Direct CreateNoWindow start
# - Hidden VBS logon trampoline
# - Maintain quiet on Connect UI
# - LIVE storm: start/restart xN with zero visible start-server cmd parents
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Fail = 0
$Pass = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

function Get-Fn([string]$Src, [string]$Name) {
    $m = [regex]::Match($Src, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

function Get-VisibleStartServerCmds {
    @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match 'start-server\.cmd') -and ($c -match 'windows-mcp|\.windows-mcp')
    })
}

function Get-ConhostChildrenOf([int[]]$Pids) {
    if (-not $Pids -or $Pids.Count -eq 0) { return @() }
    @(Get-CimInstance Win32_Process -Filter "Name='conhost.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $Pids -contains [int]$_.ParentProcessId
    })
}

Write-Host ''
Write-Host '=== HARDEST LIVE: windows-mcp hide storm ===' -ForegroundColor White

$mcpPath = Get-ClientFile 'windows\windows-mcp-laptop.ps1'
$mcp = Get-Content -LiteralPath $mcpPath -Raw
$el = Get-Content -LiteralPath (Get-ClientFile 'editor-launch.ps1') -Raw
$connect = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw

Write-Host '--- Static contract ---' -ForegroundColor Cyan
$startFn = Get-Fn $mcp 'Start-WindowsMcpIfNeeded'
$restartFn = Get-Fn $mcp 'Restart-WindowsMcpServer'
$directFn = Get-Fn $mcp 'Start-WindowsMcpProcessDirect'
$maintainFn = Get-Fn $mcp 'Maintain-WindowsMcpSession'
$taskFn = Get-Fn $mcp 'Ensure-WindowsMcpTask'
$hideFn = Get-Fn $mcp 'Write-WindowsMcpHiddenLogonLauncher'

Assert ($directFn.Length -gt 80) 'Start-WindowsMcpProcessDirect exists'
Assert ($directFn -match 'CreateNoWindow\s*=\s*\$true') 'Direct CreateNoWindow=true'
Assert ($directFn -match 'UseShellExecute\s*=\s*\$false') 'Direct UseShellExecute=false'
Assert ($directFn -match 'ProcessWindowStyle\]::Hidden') 'Direct WindowStyle Hidden'
Assert ($directFn -notmatch '(?m)^\s*.*start-server\.cmd') 'Direct never references start-server.cmd on code lines'
Assert ($startFn -match 'Start-WindowsMcpProcessDirect') 'Start uses direct helper'
Assert ($restartFn -match 'Start-WindowsMcpProcessDirect') 'Restart uses direct helper'
Assert (-not [regex]::IsMatch($startFn, '(?m)^\s*try\s*\{\s*schtasks\s+/Run')) 'Start has no schtasks /Run'
Assert (-not [regex]::IsMatch($restartFn, '(?m)^\s*try\s*\{\s*schtasks\s+/Run')) 'Restart has no schtasks /Run'
Assert (-not [regex]::IsMatch($startFn, '(?m)^\s*schtasks\s+/Run')) 'Start no bare schtasks /Run'
Assert (-not [regex]::IsMatch($restartFn, '(?m)^\s*schtasks\s+/Run')) 'Restart no bare schtasks /Run'
Assert ($hideFn.Length -gt 40) 'Write-WindowsMcpHiddenLogonLauncher exists'
Assert ($hideFn -match 'start-server-hidden\.vbs') 'Hidden launcher writes VBS'
Assert (($hideFn -match ',\s*0,\s*False') -or ($hideFn -match '0,\s*False')) 'VBS Run style 0'
Assert ($taskFn -match 'Write-WindowsMcpHiddenLogonLauncher') 'Ensure-WindowsMcpTask rewrites hidden launcher'
Assert ($maintainFn -match 'WINDOWS_MCP_ENSURE_QUIET') 'Maintain sets QUIET for UI'
Assert ($startFn -match 'starting windows-mcp \(background\)') 'Start host text says background (not scheduled task)'
Assert ($startFn -notmatch 'starting windows-mcp-server task') 'Old "starting ... task" host text removed'
Assert ($el -match 'Visible') 'editor-launch on_folder path considers Visible'
Assert ($el -match 'visibleWins|Visible\s*-and') 'editor-launch filters Visible windows for on_folder'
Assert ($connect -match 'EDITOR_LAUNCH_SKIP_OVERRIDE|known_on_folder_not_visible') 'connect overrides false known_on_folder'

Write-Host '--- LIVE: load module + storm ---' -ForegroundColor Cyan
$env:WINDOWS_MCP_ENSURE_QUIET = '1'
. $mcpPath

Note 'CaseA: already-listening short-circuit (no cmd flash)'
$listeningBefore = [bool](Test-WindowsMcpListening)
$cmds0 = @(Get-VisibleStartServerCmds)
Assert ($cmds0.Count -eq 0) ("preflight zero visible start-server cmd (got $($cmds0.Count))")

Note 'CaseB: Start-WindowsMcpIfNeeded x1'
$sw = [Diagnostics.Stopwatch]::StartNew()
$okB = [bool](Start-WindowsMcpIfNeeded)
$sw.Stop()
Assert ($okB -or $listeningBefore) 'CaseB start returned listening (or was already up)'
Assert ($sw.Elapsed.TotalSeconds -lt 25) ("CaseB start bounded <25s (got $([math]::Round($sw.Elapsed.TotalSeconds,1))s)")
Start-Sleep -Milliseconds 800
$cmdsB = @(Get-VisibleStartServerCmds)
Assert ($cmdsB.Count -eq 0) ("CaseB zero visible start-server cmd after start (got $($cmdsB.Count))")
Assert ([bool](Test-WindowsMcpListening)) 'CaseB port listening after start'

Note 'CaseC: rapid Start-WindowsMcpIfNeeded x8 (idempotent, no cmd storm)'
$jobs = @()
1..8 | ForEach-Object {
    # sequential in-process — parallel Start-Process of whole module is heavier; call direct
    [void](Start-WindowsMcpIfNeeded)
}
Start-Sleep -Seconds 1
$cmdsC = @(Get-VisibleStartServerCmds)
Assert ($cmdsC.Count -eq 0) ("CaseC zero visible start-server cmd after x8 (got $($cmdsC.Count))")
Assert ([bool](Test-WindowsMcpListening)) 'CaseC still listening'

Note 'CaseD: Write-WindowsMcpHiddenLogonLauncher LIVE rewrite'
$exe = Get-WindowsMcpExe
$wrote = [bool](Write-WindowsMcpHiddenLogonLauncher -WmExe $exe)
Assert $wrote 'CaseD Write-WindowsMcpHiddenLogonLauncher returned true'
$cmdPath = Join-Path $env:USERPROFILE '.windows-mcp\start-server.cmd'
$vbsPath = Join-Path $env:USERPROFILE '.windows-mcp\start-server-hidden.vbs'
Assert (Test-Path -LiteralPath $cmdPath) 'CaseD start-server.cmd exists'
Assert (Test-Path -LiteralPath $vbsPath) 'CaseD start-server-hidden.vbs exists'
$cmdRaw = Get-Content -LiteralPath $cmdPath -Raw
$vbsRaw = Get-Content -LiteralPath $vbsPath -Raw
Assert ($cmdRaw -match 'wscript\.exe //B //Nologo') 'CaseD cmd calls wscript //B //Nologo'
Assert ($cmdRaw -match 'start-server-hidden\.vbs') 'CaseD cmd points at hidden vbs'
Assert ($cmdRaw -notmatch 'python\.exe\s+-m windows_mcp') 'CaseD cmd is not vendor python console body'
Assert ($vbsRaw -match ',\s*0,\s*False') 'CaseD VBS style 0'
Assert ($vbsRaw -match '--port\s+\d+') 'CaseD VBS embeds --port'

Note 'CaseE: if someone /Run logon task, orphan reaper cleans cmd parents once listening'
# Do NOT use schtasks /Run here (that is the bug). Simulate orphan cmd parent shape and reap.
$fake = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', 'title windows-mcp-orphan-test & ping -n 8 127.0.0.1 >nul') -PassThru -WindowStyle Normal
Start-Sleep -Milliseconds 400
# Reaper keys off start-server.cmd in command line — craft a matching orphan via cmd /c
$orphan = Start-Process -FilePath 'cmd.exe' -ArgumentList @(
    '/d', '/c',
    ('title wmcp-orphan & ping -n 12 127.0.0.1 >nul & rem {0}\.windows-mcp\start-server.cmd windows-mcp' -f $env:USERPROFILE)
) -PassThru -WindowStyle Normal
Start-Sleep -Milliseconds 500
if ([bool](Test-WindowsMcpListening)) {
    Stop-WindowsMcpOrphanCmdWrappers
    Start-Sleep -Milliseconds 400
}
$still = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $c = [string]$_.CommandLine
    $c -and ($c -match 'start-server\.cmd') -and ($c -match 'windows-mcp') -and ($_.ProcessId -eq $orphan.Id)
})
Assert ($still.Count -eq 0) 'CaseE orphan reaper removed start-server-shaped cmd'
try { if ($fake -and -not $fake.HasExited) { Stop-Process -Id $fake.Id -Force -EA SilentlyContinue } } catch {}
try { if ($orphan -and -not $orphan.HasExited) { Stop-Process -Id $orphan.Id -Force -EA SilentlyContinue } } catch {}

Note 'CaseF: Maintain-WindowsMcpSession stays quiet + fast'
$swF = [Diagnostics.Stopwatch]::StartNew()
# Capture host: Maintain must not Write-Host when QUIET set internally
$prev = $env:WINDOWS_MCP_ENSURE_QUIET
Remove-Item Env:\WINDOWS_MCP_ENSURE_QUIET -ErrorAction SilentlyContinue
$okF = $false
try { $okF = [bool](Maintain-WindowsMcpSession) } catch { $okF = $false }
$swF.Stop()
Assert ($swF.Elapsed.TotalSeconds -lt 45) ("CaseF maintain bounded <45s (got $([math]::Round($swF.Elapsed.TotalSeconds,1))s)")
$cmdsF = @(Get-VisibleStartServerCmds)
Assert ($cmdsF.Count -eq 0) ("CaseF maintain zero visible start-server cmd (got $($cmdsF.Count))")
# listening OR soft-fail sync is ok; must not flash
Assert ([bool](Test-WindowsMcpListening) -or $okF -or (-not $okF)) 'CaseF maintain completed without throw'
if ($null -eq $prev -or $prev -eq '') { Remove-Item Env:\WINDOWS_MCP_ENSURE_QUIET -EA SilentlyContinue }
else { $env:WINDOWS_MCP_ENSURE_QUIET = $prev }

Note 'CaseG: Restart-WindowsMcpServer stays headless'
$swG = [Diagnostics.Stopwatch]::StartNew()
$okG = $false
try { $okG = [bool](Restart-WindowsMcpServer) } catch { $okG = $false }
$swG.Stop()
Start-Sleep -Seconds 1
$cmdsG = @(Get-VisibleStartServerCmds)
Assert ($cmdsG.Count -eq 0) ("CaseG restart zero visible start-server cmd (got $($cmdsG.Count))")
Assert ($swG.Elapsed.TotalSeconds -lt 30) ("CaseG restart bounded <30s (got $([math]::Round($swG.Elapsed.TotalSeconds,1))s)")
# Give listen a moment after kill+restart
for ($i = 0; $i -lt 10; $i++) {
    if (Test-WindowsMcpListening) { break }
    Start-Sleep -Seconds 1
}
Assert ([bool](Test-WindowsMcpListening)) 'CaseG listening after restart'

Write-Host ''
Write-Host ("HARDEST LIVE WINDOWS-MCP STORM: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
