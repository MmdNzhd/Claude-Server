#Requires -Version 5.1
# HARDEST++ LIVE: windows-mcp headless under adversarial load.
# Static contracts + LIVE storms: start/restart/maintain/VBS/vendor-cmd plant/
# parallel out-of-process jobs / kill-recover / conhost+MainWindow sampling /
# HTTP listen probe. Zero visible start-server.cmd parents allowed.
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

function Get-WmcpServeProcesses {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $n = [string]$_.Name
        $c -and (
            ($n -match 'windows-mcp' -and $c -match 'serve') -or
            ($n -match 'python' -and $c -match 'windows_mcp\s+serve')
        )
    })
}

function Get-VisibleConsoleLeaks {
    # Any cmd whose title/cmdline screams windows-mcp start path, or conhost parented by those cmds.
    $cmds = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match 'start-server\.cmd|windows-mcp-server|wmcp-orphan|\.windows-mcp\\start-server')
    })
    $pids = @($cmds | ForEach-Object { [int]$_.ProcessId })
    $conhosts = @()
    if ($pids.Count -gt 0) {
        $conhosts = @(Get-CimInstance Win32_Process -Filter "Name='conhost.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $pids -contains [int]$_.ParentProcessId
        })
    }
    [pscustomobject]@{ Cmds = $cmds; Conhosts = $conhosts; Total = ($cmds.Count + $conhosts.Count) }
}

function Assert-NoWmcpCmdFlash([string]$Label) {
    $leaks = Get-VisibleConsoleLeaks
    Assert ($leaks.Total -eq 0) ("$Label zero wmcp cmd/conhost leaks (cmd=$($leaks.Cmds.Count) conhost=$($leaks.Conhosts.Count))")
}

function Wait-Listening([int]$Sec = 12) {
    for ($i = 0; $i -lt $Sec; $i++) {
        if (Test-WindowsMcpListening) { return $true }
        Start-Sleep -Seconds 1
    }
    return [bool](Test-WindowsMcpListening)
}

function Test-LocalMcpHttp([int]$Port) {
    try {
        $req = [System.Net.HttpWebRequest]::Create(("http://127.0.0.1:{0}/mcp" -f $Port))
        $req.Method = 'POST'
        $req.ContentType = 'application/json'
        $req.Accept = 'application/json, text/event-stream'
        $req.Timeout = 4000
        $body = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"wmcp-storm","version":"0"}}}')
        $req.ContentLength = $body.Length
        $s = $req.GetRequestStream(); $s.Write($body, 0, $body.Length); $s.Close()
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        return ($code -ge 200 -and $code -lt 500) # 401/406 still proves listener is alive
    } catch {
        $msg = $_.Exception.Message + ''
        if ($msg -match '401|406|415|400|405') { return $true }
        try {
            if ($_.Exception.Response) {
                $code = [int]$_.Exception.Response.StatusCode
                return ($code -ge 200 -and $code -lt 500)
            }
        } catch {}
        return $false
    }
}

Write-Host ''
Write-Host '=== HARDEST++ LIVE: windows-mcp hide storm ===' -ForegroundColor White

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
$bgFn = Get-Fn $mcp 'Start-WindowsMcpEnsureBackground'

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
Assert ($maintainFn -match 'finally') 'Maintain restores QUIET in finally'
Assert ($startFn -match 'starting windows-mcp \(background\)') 'Start host text says background (not scheduled task)'
Assert ($startFn -notmatch 'starting windows-mcp-server task') 'Old "starting ... task" host text removed'
# Get-Fn truncates on nested here-strings; assert against full module source.
Assert ($mcp -match "(?s)function\s+Start-WindowsMcpEnsureBackground.*?-WindowStyle',\s*'Hidden'") 'Background ensure arglist uses -WindowStyle Hidden'
Assert ($mcp -match "(?s)function\s+Start-WindowsMcpEnsureBackground.*?Start-Process[\s\S]{0,200}?-WindowStyle Hidden") 'Background ensure Start-Process uses -WindowStyle Hidden'
Assert ($el -match 'Visible') 'editor-launch on_folder path considers Visible'
Assert ($el -match 'visibleWins|Visible\s*-and') 'editor-launch filters Visible windows for on_folder'
Assert ($connect -match 'EDITOR_LAUNCH_SKIP_OVERRIDE|known_on_folder_not_visible') 'connect overrides false known_on_folder'
Assert ($connect -match 'Start-WindowsMcpEnsureBackground') 'connect starts MCP ensure in background'
Assert ($connect -match 'Maintain-WindowsMcpSession') 'connect mid-session maintain hook present'

Write-Host '--- LIVE: load module + adversarial storm ---' -ForegroundColor Cyan
$env:WINDOWS_MCP_ENSURE_QUIET = '1'
. $mcpPath

Note 'CaseA: preflight clean'
Assert-NoWmcpCmdFlash 'CaseA'

Note 'CaseB: Start-WindowsMcpIfNeeded x1 (tight bound)'
$sw = [Diagnostics.Stopwatch]::StartNew()
$okB = [bool](Start-WindowsMcpIfNeeded)
$sw.Stop()
Assert $okB 'CaseB start returned true'
Assert ($sw.Elapsed.TotalSeconds -lt 12) ("CaseB start bounded <12s (got $([math]::Round($sw.Elapsed.TotalSeconds,1))s)")
Assert-NoWmcpCmdFlash 'CaseB'
Assert ([bool](Test-WindowsMcpListening)) 'CaseB port listening'

Note 'CaseC: rapid Start x12 in-process'
1..12 | ForEach-Object { [void](Start-WindowsMcpIfNeeded) }
Start-Sleep -Milliseconds 600
Assert-NoWmcpCmdFlash 'CaseC'
Assert ([bool](Test-WindowsMcpListening)) 'CaseC still listening'

Note 'CaseD: plant VENDOR start-server.cmd then Ensure rewrite'
$cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
$cmdPath = Join-Path $cfgDir 'start-server.cmd'
$vbsPath = Join-Path $cfgDir 'start-server-hidden.vbs'
$lport = Get-WindowsMcpLocalPort
$exe = Get-WindowsMcpExe
# Plant old vendor body (the flashy one)
$vendor = "@echo off`r`nsetlocal`r`nC:\Windows\System32\cmd.exe /c echo VENDOR_FLASH & python.exe -m windows_mcp serve --transport streamable-http --host 127.0.0.1 --port $lport`r`n"
Set-Content -LiteralPath $cmdPath -Value $vendor -Encoding ASCII
Assert ((Get-Content -LiteralPath $cmdPath -Raw) -match 'python\.exe\s+-m windows_mcp') 'CaseD planted vendor console body'
$taskOk = [bool](Ensure-WindowsMcpTask -WmExe $exe)
Assert $taskOk 'CaseD Ensure-WindowsMcpTask ok after plant'
$cmdRaw = Get-Content -LiteralPath $cmdPath -Raw
$vbsRaw = Get-Content -LiteralPath $vbsPath -Raw
Assert ($cmdRaw -match 'wscript\.exe //B //Nologo') 'CaseD rewrite: cmd is wscript trampoline'
Assert ($cmdRaw -notmatch 'python\.exe\s+-m windows_mcp') 'CaseD rewrite removed vendor python body'
Assert ($vbsRaw -match ',\s*0,\s*False') 'CaseD rewrite VBS style 0'
Assert ($vbsRaw -match ("--port\s+{0}" -f [regex]::Escape("$lport"))) ("CaseD VBS port=$lport")
Assert-NoWmcpCmdFlash 'CaseD'

Note 'CaseE: orphan reaper x3 shaped cmds'
$orphans = @()
1..3 | ForEach-Object {
    $orphans += Start-Process -FilePath 'cmd.exe' -ArgumentList @(
        '/d', '/c',
        ('title wmcp-orphan-{0} & ping -n 20 127.0.0.1 >nul & rem {1}\.windows-mcp\start-server.cmd windows-mcp' -f $_, $env:USERPROFILE)
    ) -PassThru -WindowStyle Normal
}
Start-Sleep -Milliseconds 700
Assert ([bool](Test-WindowsMcpListening)) 'CaseE listening before reap'
Stop-WindowsMcpOrphanCmdWrappers
Start-Sleep -Milliseconds 500
$alive = @($orphans | Where-Object { $_ -and -not $_.HasExited })
Assert ($alive.Count -eq 0) ("CaseE all 3 orphans reaped (alive=$($alive.Count))")
Assert-NoWmcpCmdFlash 'CaseE'
$alive | ForEach-Object { try { Stop-Process -Id $_.Id -Force -EA SilentlyContinue } catch {} }

Note 'CaseF: Maintain x5 wave (quiet + no flash)'
$prev = $env:WINDOWS_MCP_ENSURE_QUIET
Remove-Item Env:\WINDOWS_MCP_ENSURE_QUIET -ErrorAction SilentlyContinue
$swF = [Diagnostics.Stopwatch]::StartNew()
1..5 | ForEach-Object { try { [void](Maintain-WindowsMcpSession) } catch {} }
$swF.Stop()
Assert ($swF.Elapsed.TotalSeconds -lt 60) ("CaseF maintain x5 <60s (got $([math]::Round($swF.Elapsed.TotalSeconds,1))s)")
Assert-NoWmcpCmdFlash 'CaseF'
if ($null -eq $prev -or $prev -eq '') { Remove-Item Env:\WINDOWS_MCP_ENSURE_QUIET -EA SilentlyContinue }
else { $env:WINDOWS_MCP_ENSURE_QUIET = $prev }

Note 'CaseG: Restart headless + recover listen'
$swG = [Diagnostics.Stopwatch]::StartNew()
[void](Restart-WindowsMcpServer)
$swG.Stop()
Assert ($swG.Elapsed.TotalSeconds -lt 25) ("CaseG restart <25s (got $([math]::Round($swG.Elapsed.TotalSeconds,1))s)")
Assert-NoWmcpCmdFlash 'CaseG'
Assert (Wait-Listening 12) 'CaseG listening after restart'

Note 'CaseH: kill listener then Start recover (no cmd)'
$lport = Get-WindowsMcpLocalPort
try {
    Get-NetTCPConnection -LocalPort $lport -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
} catch {}
Start-Sleep -Milliseconds 500
Assert (-not (Test-WindowsMcpListening)) 'CaseH listener killed'
$swH = [Diagnostics.Stopwatch]::StartNew()
[void](Start-WindowsMcpIfNeeded)
$swH.Stop()
Assert ($swH.Elapsed.TotalSeconds -lt 12) ("CaseH recover start <12s (got $([math]::Round($swH.Elapsed.TotalSeconds,1))s)")
Assert (Wait-Listening 12) 'CaseH listening after recover'
Assert-NoWmcpCmdFlash 'CaseH'

Note 'CaseI: double-wave restart (kill stress)'
1..2 | ForEach-Object {
    [void](Restart-WindowsMcpServer)
    Assert-NoWmcpCmdFlash ("CaseI wave$_")
}
Assert (Wait-Listening 12) 'CaseI listening after double restart'

Note 'CaseJ: parallel out-of-process Start jobs x6'
$runner = Join-Path $env:TEMP ('wmcp-storm-job-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
@'
param([string]$ModulePath)
$ErrorActionPreference = "Continue"
$env:WINDOWS_MCP_ENSURE_QUIET = "1"
. $ModulePath
[void](Start-WindowsMcpIfNeeded)
exit 0
'@ | Set-Content -LiteralPath $runner -Encoding UTF8
$procs = @()
1..6 | ForEach-Object {
    $procs += Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $runner, '-ModulePath', $mcpPath
    ) -PassThru -WindowStyle Hidden
}
$deadline = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $deadline) {
    $running = @($procs | Where-Object { $_ -and -not $_.HasExited })
    if ($running.Count -eq 0) { break }
    Start-Sleep -Milliseconds 400
}
$stillRun = @($procs | Where-Object { $_ -and -not $_.HasExited })
Assert ($stillRun.Count -eq 0) ("CaseJ all 6 jobs finished (alive=$($stillRun.Count))")
$stillRun | ForEach-Object { try { Stop-Process -Id $_.Id -Force -EA SilentlyContinue } catch {} }
Start-Sleep -Seconds 1
Assert-NoWmcpCmdFlash 'CaseJ'
Assert ([bool](Test-WindowsMcpListening)) 'CaseJ listening after parallel jobs'
Remove-Item -LiteralPath $runner -Force -EA SilentlyContinue

Note 'CaseK: serve process has no visible MainWindowHandle'
$serves = @(Get-WmcpServeProcesses)
Assert ($serves.Count -ge 1) ("CaseK at least one serve process (got $($serves.Count))")
$visibleMain = 0
foreach ($sp in $serves) {
    try {
        $wp = [Diagnostics.Process]::GetProcessById([int]$sp.ProcessId)
        if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $visibleMain++ }
    } catch {}
}
Assert ($visibleMain -eq 0) ("CaseK serve processes MainWindowHandle=0 (visible=$visibleMain)")

Note 'CaseL: HTTP hit on local MCP port proves real listener'
$httpOk = Test-LocalMcpHttp -Port ([int]$lport)
Assert $httpOk ("CaseL HTTP POST /mcp on :$lport responds (listener alive)")

Note 'CaseM: wscript //B hidden VBS launch (logon path) — no cmd flash'
# End current listener owners carefully then use VBS path once
try {
    Get-NetTCPConnection -LocalPort $lport -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
} catch {}
Start-Sleep -Milliseconds 400
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$pV = Start-Process -FilePath $wscript -ArgumentList @('//B', '//Nologo', $vbsPath) -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
Assert-NoWmcpCmdFlash 'CaseM'
Assert (Wait-Listening 12) 'CaseM listening after hidden VBS'
try { if ($pV -and -not $pV.HasExited) { } } catch {}

Note 'CaseN: mixed maintain+start+restart burst'
$swN = [Diagnostics.Stopwatch]::StartNew()
1..3 | ForEach-Object {
    try { [void](Maintain-WindowsMcpSession) } catch {}
    try { [void](Start-WindowsMcpIfNeeded) } catch {}
}
try { [void](Restart-WindowsMcpServer) } catch {}
$swN.Stop()
Assert ($swN.Elapsed.TotalSeconds -lt 45) ("CaseN mixed burst <45s (got $([math]::Round($swN.Elapsed.TotalSeconds,1))s)")
Assert-NoWmcpCmdFlash 'CaseN'
Assert (Wait-Listening 12) 'CaseN listening after mixed burst'

Note 'CaseO: final leak sample (3s window)'
$leakHits = 0
1..6 | ForEach-Object {
    $leaks = Get-VisibleConsoleLeaks
    if ($leaks.Total -gt 0) { $leakHits++ }
    Start-Sleep -Milliseconds 500
}
Assert ($leakHits -eq 0) ("CaseO zero leak samples over 3s (hits=$leakHits)")
Assert ([bool](Test-WindowsMcpListening)) 'CaseO still listening at end'

Write-Host ''
Write-Host ("HARDEST++ LIVE WINDOWS-MCP STORM: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
