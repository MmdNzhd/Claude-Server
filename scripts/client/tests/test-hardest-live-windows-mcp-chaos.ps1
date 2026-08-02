#Requires -Version 5.1
# CHAOS / HARDEST LIVE: windows-mcp under abuse.
# Builds on harder-live-windows-mcp-storm with:
#  - schtasks.exe spawn guard during Start/Restart/Maintain
#  - port-hold conflict + recover
#  - broken VBS / broken cmd repair
#  - 12-way out-of-process restart+start race
#  - 20s soak sampler (cmd/conhost/schtasks)
#  - Ensure-WindowsMcp quiet path
#  - auth-rotate Restart path
#  - titled-cmd / MainWindow / HTTP multi-hit
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Fail = 0
$Pass = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

function Get-WmcpCmdLeaks {
    @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match 'start-server\.cmd|windows-mcp-server|\.windows-mcp\\start-server|wmcp-orphan')
    })
}

function Get-SchtasksSpawns {
    @(Get-CimInstance Win32_Process -Filter "Name='schtasks.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match '/Run') -and ($c -match 'windows-mcp-server')
    })
}

function Assert-Clean([string]$Label) {
    $cmds = @(Get-WmcpCmdLeaks)
    $runs = @(Get-SchtasksSpawns)
    Assert ($cmds.Count -eq 0) ("$Label zero wmcp cmd leaks (got $($cmds.Count))")
    Assert ($runs.Count -eq 0) ("$Label zero schtasks /Run windows-mcp-server (got $($runs.Count))")
}

function Wait-Listening([int]$Sec = 15) {
    for ($i = 0; $i -lt $Sec; $i++) {
        if (Test-WindowsMcpListening) { return $true }
        Start-Sleep -Seconds 1
    }
    return [bool](Test-WindowsMcpListening)
}

function Stop-ListenersOnPort([int]$Port) {
    try {
        Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Test-LocalMcpHttp([int]$Port) {
    try {
        $req = [System.Net.HttpWebRequest]::Create(("http://127.0.0.1:{0}/mcp" -f $Port))
        $req.Method = 'POST'
        $req.ContentType = 'application/json'
        $req.Accept = 'application/json, text/event-stream'
        $req.Timeout = 3500
        $body = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"wmcp-chaos","version":"0"}}}')
        $req.ContentLength = $body.Length
        $s = $req.GetRequestStream(); $s.Write($body, 0, $body.Length); $s.Close()
        $resp = $req.GetResponse(); $code = [int]$resp.StatusCode; $resp.Close()
        return ($code -ge 200 -and $code -lt 500)
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

function Start-GuardSampler {
    param([string]$OutFile, [int]$Seconds = 20)
    $script = @'
param([string]$OutFile,[int]$Seconds)
$end = (Get-Date).AddSeconds($Seconds)
$hits = New-Object System.Collections.Generic.List[string]
while ((Get-Date) -lt $end) {
  try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
      $n = [string]$_.Name; $c = [string]$_.CommandLine
      if ($n -eq 'schtasks.exe' -and $c -match '/Run' -and $c -match 'windows-mcp-server') {
        [void]$hits.Add(('SCHTASKS_RUN {0}' -f $c))
      }
      if ($n -eq 'cmd.exe' -and $c -match 'start-server\.cmd' -and $c -match 'windows-mcp|\.windows-mcp') {
        [void]$hits.Add(('CMD_START_SERVER {0}' -f $c))
      }
    }
  } catch {}
  Start-Sleep -Milliseconds 250
}
$hits | Set-Content -LiteralPath $OutFile -Encoding UTF8
'@
    $tmp = Join-Path $env:TEMP ('wmcp-guard-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $tmp, '-OutFile', $OutFile, '-Seconds', "$Seconds"
    ) -PassThru -WindowStyle Hidden
    return [pscustomobject]@{ Proc = $p; Script = $tmp; OutFile = $OutFile }
}

Write-Host ''
Write-Host '=== CHAOS HARDEST LIVE: windows-mcp ===' -ForegroundColor White

$mcpPath = Get-ClientFile 'windows\windows-mcp-laptop.ps1'
$mcp = Get-Content -LiteralPath $mcpPath -Raw

# --- Static must-not-regress ---
Assert ($mcp -notmatch '(?m)^\s*try\s*\{\s*schtasks\s+/Run') 'static: no try{ schtasks /Run'
Assert ($mcp -notmatch '(?m)^\s*schtasks\s+/Run') 'static: no bare schtasks /Run'
Assert ($mcp -match 'Start-WindowsMcpProcessDirect') 'static: direct start present'
Assert ($mcp -match 'Write-WindowsMcpHiddenLogonLauncher') 'static: hidden logon launcher present'
Assert ($mcp -match 'CreateNoWindow\s*=\s*\$true') 'static: CreateNoWindow=true'
Assert ($mcp -match 'WINDOWS_MCP_ENSURE_QUIET') 'static: quiet maintain'

$env:WINDOWS_MCP_ENSURE_QUIET = '1'
. $mcpPath

$lport = [int](Get-WindowsMcpLocalPort)
$exe = Get-WindowsMcpExe
$cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
$cmdPath = Join-Path $cfgDir 'start-server.cmd'
$vbsPath = Join-Path $cfgDir 'start-server-hidden.vbs'
Assert ($lport -gt 0) ("local port resolved ($lport)")
Assert ([bool]$exe) 'windows-mcp.exe available'

Note 'Chaos0: baseline clean + listen'
[void](Start-WindowsMcpIfNeeded)
Assert (Wait-Listening 12) 'Chaos0 listening'
Assert-Clean 'Chaos0'

Note 'Chaos1: schtasks-spawn guard during Start/Restart/Maintain burst'
$guardOut = Join-Path $env:TEMP ('wmcp-guard-hits-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
$guard = Start-GuardSampler -OutFile $guardOut -Seconds 22
Start-Sleep -Milliseconds 300
$sw1 = [Diagnostics.Stopwatch]::StartNew()
1..4 | ForEach-Object {
    try { [void](Maintain-WindowsMcpSession) } catch {}
    try { [void](Start-WindowsMcpIfNeeded) } catch {}
}
try { [void](Restart-WindowsMcpServer) } catch {}
1..3 | ForEach-Object { try { [void](Start-WindowsMcpIfNeeded) } catch {} }
$sw1.Stop()
# wait guard
$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
    if ($guard.Proc.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
if (-not $guard.Proc.HasExited) { try { Stop-Process -Id $guard.Proc.Id -Force -EA SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 400
$hits = @()
if (Test-Path -LiteralPath $guardOut) { $hits = @(Get-Content -LiteralPath $guardOut -EA SilentlyContinue) }
Assert ($hits.Count -eq 0) ("Chaos1 guard zero schtasks/cmd hits (got $($hits.Count): $($hits[0]))")
# Bound is loose on busy laptops (parallel MCP/python spawn); functional gates below are hard.
Assert ($sw1.Elapsed.TotalSeconds -lt 90) ("Chaos1 burst <90s (got $([math]::Round($sw1.Elapsed.TotalSeconds,1))s)")
Assert-Clean 'Chaos1'
Assert (Wait-Listening 12) 'Chaos1 listening'
Remove-Item -LiteralPath $guard.Script, $guardOut -Force -EA SilentlyContinue

Note 'Chaos2: port-hold conflict then recover'
Stop-ListenersOnPort $lport
Start-Sleep -Milliseconds 400
$holder = $null
try {
    $holder = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $lport)
    $holder.Start()
} catch { $holder = $null }
Assert ($null -ne $holder) 'Chaos2 held listen port with TcpListener'
# Start should fail soft (not listen) without flashing cmd
$okHold = $true
try { $okHold = [bool](Start-WindowsMcpIfNeeded) } catch { $okHold = $false }
Assert-Clean 'Chaos2 during hold'
# Release and recover
try { if ($holder) { $holder.Stop() } } catch {}
Start-Sleep -Milliseconds 300
$sw2 = [Diagnostics.Stopwatch]::StartNew()
[void](Start-WindowsMcpIfNeeded)
$sw2.Stop()
Assert ($sw2.Elapsed.TotalSeconds -lt 15) ("Chaos2 recover <15s (got $([math]::Round($sw2.Elapsed.TotalSeconds,1))s)")
Assert (Wait-Listening 15) 'Chaos2 listening after release'
Assert-Clean 'Chaos2 after recover'

Note 'Chaos3: corrupt VBS + broken cmd - Ensure repairs (under EAP=Stop)'
# Prove rewrite survives caller's Stop preference (native install stderr).
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $vbsPath -Value 'this is not valid vbs!!!!!' -Encoding ASCII
Set-Content -LiteralPath $cmdPath -Value "@echo off`r`necho FLASH& python.exe -m windows_mcp serve --port 8000`r`n" -Encoding ASCII
Assert ((Get-Content $cmdPath -Raw) -match 'python\.exe') 'Chaos3 planted broken vendor cmd'
$exeNow = Get-WindowsMcpExe
Assert ([bool]$exeNow) 'Chaos3 windows-mcp.exe still available'
$rep = $false
try { $rep = [bool](Ensure-WindowsMcpTask -WmExe $exeNow) } catch { $rep = $false }
Assert $rep 'Chaos3 Ensure-WindowsMcpTask repaired'
$cmdRaw = Get-Content $cmdPath -Raw
$vbsRaw = Get-Content $vbsPath -Raw
Assert ($cmdRaw -match 'wscript\.exe //B //Nologo') 'Chaos3 cmd is wscript trampoline'
Assert ($cmdRaw -notmatch 'python\.exe') 'Chaos3 vendor python removed'
Assert ($vbsRaw -match 'CreateObject\("WScript\.Shell"\)') 'Chaos3 VBS valid WScript'
Assert ($vbsRaw -match ',\s*0,\s*False') 'Chaos3 VBS style 0'
Assert ($vbsRaw -match ("--port\s+{0}" -f $lport)) ("Chaos3 VBS port=$lport not 8000")
Assert-Clean 'Chaos3'

Note 'Chaos4: invoke repaired logon path via wscript (no lasting cmd)'
Stop-ListenersOnPort $lport
Start-Sleep -Milliseconds 300
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
1..3 | ForEach-Object {
    Start-Process -FilePath $wscript -ArgumentList @('//B', '//Nologo', $vbsPath) -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 400
}
Assert-Clean 'Chaos4 during VBS x3'
Assert (Wait-Listening 15) 'Chaos4 listening via VBS path'
Assert-Clean 'Chaos4 after listen'

Note 'Chaos5: 12-way out-of-process race (start+restart mixed)'
$runner = Join-Path $env:TEMP ('wmcp-chaos-race-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
@'
param([string]$ModulePath,[string]$Mode)
$ErrorActionPreference = "Continue"
$env:WINDOWS_MCP_ENSURE_QUIET = "1"
. $ModulePath
if ($Mode -eq 'restart') { [void](Restart-WindowsMcpServer) }
else { [void](Start-WindowsMcpIfNeeded) }
exit 0
'@ | Set-Content -LiteralPath $runner -Encoding UTF8
$procs = @()
1..12 | ForEach-Object {
    $mode = if ($_ % 3 -eq 0) { 'restart' } else { 'start' }
    $procs += Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $runner, '-ModulePath', $mcpPath, '-Mode', $mode
    ) -PassThru -WindowStyle Hidden
}
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    if (@($procs | Where-Object { $_ -and -not $_.HasExited }).Count -eq 0) { break }
    Start-Sleep -Milliseconds 400
}
$alive = @($procs | Where-Object { $_ -and -not $_.HasExited })
Assert ($alive.Count -eq 0) ("Chaos5 all 12 race jobs done (alive=$($alive.Count))")
$alive | ForEach-Object { try { Stop-Process -Id $_.Id -Force -EA SilentlyContinue } catch {} }
Start-Sleep -Seconds 1
Assert-Clean 'Chaos5'
Assert (Wait-Listening 15) 'Chaos5 listening after race'
Remove-Item -LiteralPath $runner -Force -EA SilentlyContinue

Note 'Chaos6: orphan flood x8 + reap'
$orph = @()
1..8 | ForEach-Object {
    $orph += Start-Process -FilePath 'cmd.exe' -ArgumentList @(
        '/d', '/c',
        ('title chaos-orphan-{0} & ping -n 30 127.0.0.1 >nul & rem {1}\.windows-mcp\start-server.cmd windows-mcp' -f $_, $env:USERPROFILE)
    ) -PassThru -WindowStyle Normal
}
Start-Sleep -Milliseconds 800
Assert ([bool](Test-WindowsMcpListening)) 'Chaos6 listening before reap'
Stop-WindowsMcpOrphanCmdWrappers
Start-Sleep -Milliseconds 600
$still = @($orph | Where-Object { $_ -and -not $_.HasExited })
Assert ($still.Count -eq 0) ("Chaos6 all 8 orphans reaped (alive=$($still.Count))")
$still | ForEach-Object { try { Stop-Process -Id $_.Id -Force -EA SilentlyContinue } catch {} }
Assert-Clean 'Chaos6'

Note 'Chaos7: auth-rotate Restart path (flag simulation)'
$script:WindowsMcpAuthRotated = $true
# Restart-WindowsMcpServer is what Ensure calls after rotate
$sw7 = [Diagnostics.Stopwatch]::StartNew()
$ok7 = [bool](Restart-WindowsMcpServer)
$sw7.Stop()
$script:WindowsMcpAuthRotated = $false
Assert $ok7 'Chaos7 Restart after auth-rotate returned true'
Assert ($sw7.Elapsed.TotalSeconds -lt 25) ("Chaos7 restart <25s (got $([math]::Round($sw7.Elapsed.TotalSeconds,1))s)")
Assert-Clean 'Chaos7'
Assert (Wait-Listening 12) 'Chaos7 listening'

Note 'Chaos8: Ensure-WindowsMcp full quiet path (may take longer)'
$env:WINDOWS_MCP_ENSURE_QUIET = '1'
$sw8 = [Diagnostics.Stopwatch]::StartNew()
$er = $null
try { $er = Ensure-WindowsMcp } catch { $er = $null }
$sw8.Stop()
Assert ($null -ne $er) 'Chaos8 Ensure-WindowsMcp returned object'
Assert ($sw8.Elapsed.TotalSeconds -lt 120) ("Chaos8 Ensure <120s (got $([math]::Round($sw8.Elapsed.TotalSeconds,1))s)")
Assert-Clean 'Chaos8'
Assert ([bool]$er.Listening -or (Test-WindowsMcpListening)) 'Chaos8 listening after Ensure'
# Synced may fail without SshX in isolated load - do not hard-fail sync here
Assert ($er.PSObject.Properties.Name -contains 'Synced') 'Chaos8 result has Synced property'

Note 'Chaos9: serve MainWindowHandle still zero + HTTP x5'
$serves = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $c = [string]$_.CommandLine; $n = [string]$_.Name
    $c -and (($n -match 'windows-mcp' -and $c -match 'serve') -or ($n -match 'python' -and $c -match 'windows_mcp\s+serve'))
})
Assert ($serves.Count -ge 1) ("Chaos9 serve procs >=1 (got $($serves.Count))")
$vis = 0
foreach ($sp in $serves) {
    try {
        $wp = [Diagnostics.Process]::GetProcessById([int]$sp.ProcessId)
        if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $vis++ }
    } catch {}
}
Assert ($vis -eq 0) ("Chaos9 MainWindowHandle all zero (visible=$vis)")
$script:HttpHits = 0
1..5 | ForEach-Object { if (Test-LocalMcpHttp -Port $lport) { $script:HttpHits++ }; Start-Sleep -Milliseconds 200 }
Assert ($script:HttpHits -ge 3) ("Chaos9 HTTP hits >=3/5 (got $($script:HttpHits))")

Note 'Chaos10: 20s soak sampler under Maintain/Start chatter'
$soakOut = Join-Path $env:TEMP ('wmcp-soak-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
$soak = Start-GuardSampler -OutFile $soakOut -Seconds 20
$tEnd = (Get-Date).AddSeconds(18)
while ((Get-Date) -lt $tEnd) {
    try { [void](Maintain-WindowsMcpSession) } catch {}
    try { [void](Start-WindowsMcpIfNeeded) } catch {}
    Start-Sleep -Milliseconds 700
}
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    if ($soak.Proc.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
if (-not $soak.Proc.HasExited) { try { Stop-Process -Id $soak.Proc.Id -Force -EA SilentlyContinue } catch {} }
$soakHits = @()
if (Test-Path $soakOut) { $soakHits = @(Get-Content $soakOut -EA SilentlyContinue) }
Assert ($soakHits.Count -eq 0) ("Chaos10 soak zero schtasks/cmd hits (got $($soakHits.Count))")
Assert-Clean 'Chaos10'
Assert ([bool](Test-WindowsMcpListening)) 'Chaos10 still listening'
Remove-Item -LiteralPath $soak.Script, $soakOut -Force -EA SilentlyContinue

Note 'Chaos11: kill thrash x5 (stop listen -> start) no flash'
1..5 | ForEach-Object {
    Stop-ListenersOnPort $lport
    Start-Sleep -Milliseconds 200
    [void](Start-WindowsMcpIfNeeded)
    Assert-Clean ("Chaos11 iter$_")
}
Assert (Wait-Listening 15) 'Chaos11 final listening'

Note 'Chaos12: final multi-signal gate'
Assert-Clean 'Chaos12'
Assert ([bool](Test-WindowsMcpListening)) 'Chaos12 listening'
Assert (Test-LocalMcpHttp -Port $lport) 'Chaos12 HTTP ok'
$cmdFinal = @(Get-WmcpCmdLeaks)
$schFinal = @(Get-SchtasksSpawns)
Assert ($cmdFinal.Count -eq 0 -and $schFinal.Count -eq 0) 'Chaos12 dual-zero cmd+schtasks'

Write-Host ''
Write-Host ("CHAOS HARDEST LIVE WINDOWS-MCP: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
