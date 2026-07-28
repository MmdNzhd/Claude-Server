#Requires -Version 5.1
# BRUTAL LIVE: windows-mcp abuse beyond chaos.
# Hunts the class of bugs chaos already found (EAP=Stop + native stderr aborting
# before hidden-launcher rewrite) plus:
#  - readonly cmd/vbs still repaired
#  - cfg dir wiped then recreated
#  - plant-during-Ensure race
#  - auth regen under Stop
#  - Restart/Start/Maintain under Stop
#  - pure bool pipeline (no pollution)
#  - invariant: after every Ensure-WindowsMcpTask, cmd=trampoline + VBS port ok
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
        $c -and ($c -match 'start-server\.cmd|windows-mcp-server|\.windows-mcp\\start-server')
    })
}
function Get-SchtasksRuns {
    @(Get-CimInstance Win32_Process -Filter "Name='schtasks.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match '/Run') -and ($c -match 'windows-mcp-server')
    })
}
function Assert-Clean([string]$Label) {
    Assert ((Get-WmcpCmdLeaks).Count -eq 0) ("$Label zero wmcp cmd leaks")
    Assert ((Get-SchtasksRuns).Count -eq 0) ("$Label zero schtasks /Run")
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
function Plant-VendorFlash([string]$CmdPath, [string]$VbsPath) {
    Set-Content -LiteralPath $VbsPath -Value 'NOT_VALID_VBS_BRUTAL!!!!' -Encoding ASCII -Force
    Set-Content -LiteralPath $CmdPath -Value "@echo off`r`necho FLASH& python.exe -m windows_mcp serve --port 8000`r`n" -Encoding ASCII -Force
}
function Assert-HiddenLauncher([string]$Label, [string]$CmdPath, [string]$VbsPath, [int]$Port) {
    $cmdRaw = (Get-Content -LiteralPath $CmdPath -Raw -ErrorAction SilentlyContinue) + ''
    $vbsRaw = (Get-Content -LiteralPath $VbsPath -Raw -ErrorAction SilentlyContinue) + ''
    Assert ($cmdRaw -match 'wscript\.exe //B //Nologo') ("$Label cmd trampoline")
    Assert ($cmdRaw -notmatch 'python\.exe') ("$Label cmd no python")
    Assert ($cmdRaw -match 'start-server-hidden\.vbs') ("$Label cmd refs hidden vbs")
    Assert ($vbsRaw -match 'CreateObject\("WScript\.Shell"\)') ("$Label VBS WScript")
    Assert ($vbsRaw -match ',\s*0,\s*False') ("$Label VBS style 0")
    Assert ($vbsRaw -match ("--port\s+{0}" -f $Port)) ("$Label VBS port=$Port")
    Assert ($vbsRaw -notmatch '--port\s+8000') ("$Label VBS not stuck on 8000")
}
function Test-LocalMcpHttp([int]$Port) {
    try {
        $req = [System.Net.HttpWebRequest]::Create(("http://127.0.0.1:{0}/mcp" -f $Port))
        $req.Method = 'POST'
        $req.ContentType = 'application/json'
        $req.Accept = 'application/json, text/event-stream'
        $req.Timeout = 3500
        $body = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"wmcp-brutal","version":"0"}}}')
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

Write-Host ''
Write-Host '=== BRUTAL LIVE: windows-mcp abuse ===' -ForegroundColor White

$mcpPath = Get-ClientFile 'windows\windows-mcp-laptop.ps1'
$mcp = Get-Content -LiteralPath $mcpPath -Raw

# Static: install path must never return before rewrite; EAP shield present
Assert ($mcp -match 'prevEap\s*=\s*\$ErrorActionPreference') 'static: install EAP shield (prevEap)'
Assert ($mcp -match 'ErrorActionPreference\s*=\s*''Continue''') 'static: install forces Continue'
Assert ($mcp -match 'Must run even when install failed') 'static: rewrite-after-install comment'
Assert ($mcp -match '\$hidOk\s*=\s*\[bool\]\(Write-WindowsMcpHiddenLogonLauncher') 'static: hidOk rewrite gate'
Assert ($mcp -notmatch '(?m)catch\s*\{[^}]*return\s*\$false\s*\}[\s\S]{0,80}Write-WindowsMcpHiddenLogonLauncher') 'static: no early false before rewrite nearby'
Assert ($mcp -match 'IsReadOnly|ReadOnly') 'static: readonly clear before write (or will fail brutal B)'

$env:WINDOWS_MCP_ENSURE_QUIET = '1'
. $mcpPath

# Entire suite runs under Stop — this is the bug class that bit us.
$ErrorActionPreference = 'Stop'

$lport = [int](Get-WindowsMcpLocalPort)
$exe = Get-WindowsMcpExe
$cfgDir = Join-Path $env:USERPROFILE '.windows-mcp'
$cmdPath = Join-Path $cfgDir 'start-server.cmd'
$vbsPath = Join-Path $cfgDir 'start-server-hidden.vbs'
Assert ($lport -gt 0) ("port resolved ($lport)")
Assert ([bool]$exe) 'windows-mcp.exe available'

Note 'B0: baseline listen + clean under Stop'
[void](Start-WindowsMcpIfNeeded)
Assert (Wait-Listening 12) 'B0 listening'
Assert-Clean 'B0'
Assert-HiddenLauncher 'B0' $cmdPath $vbsPath $lport

Note 'B1: Ensure return is pure single bool (no pipeline pollution)'
Plant-VendorFlash $cmdPath $vbsPath
$rawOut = @(Ensure-WindowsMcpTask -WmExe $exe)
Assert ($rawOut.Count -eq 1) ("B1 single pipeline object (got $($rawOut.Count))")
Assert ($rawOut[0] -is [bool]) ("B1 type bool (got $($rawOut[0].GetType().Name))")
Assert ([bool]$rawOut[0]) 'B1 Ensure returned true'
Assert-HiddenLauncher 'B1' $cmdPath $vbsPath $lport
Assert-Clean 'B1'

Note 'B2: plant x5 alternating Ensure under Stop — invariant every round'
$allOk = $true
1..5 | ForEach-Object {
    Plant-VendorFlash $cmdPath $vbsPath
    $r = $false
    try { $r = [bool](Ensure-WindowsMcpTask -WmExe (Get-WindowsMcpExe)) } catch { $r = $false }
    if (-not $r) { $script:allOk = $false }
    $cmdRaw = (Get-Content $cmdPath -Raw) + ''
    $vbsRaw = (Get-Content $vbsPath -Raw) + ''
    if ($cmdRaw -notmatch 'wscript\.exe //B //Nologo') { $script:allOk = $false }
    if ($cmdRaw -match 'python\.exe') { $script:allOk = $false }
    if ($vbsRaw -notmatch ("--port\s+{0}" -f $lport)) { $script:allOk = $false }
}
Assert $allOk 'B2 five plant/Ensure rounds all repaired'
Assert-Clean 'B2'

Note 'B3: readonly cmd+vbs — Ensure must still rewrite'
Plant-VendorFlash $cmdPath $vbsPath
try {
    (Get-Item -LiteralPath $cmdPath).IsReadOnly = $true
    (Get-Item -LiteralPath $vbsPath).IsReadOnly = $true
} catch {}
Assert ((Get-Item $cmdPath).IsReadOnly) 'B3 planted readonly cmd'
Assert ((Get-Item $vbsPath).IsReadOnly) 'B3 planted readonly vbs'
$repRo = $false
try { $repRo = [bool](Ensure-WindowsMcpTask -WmExe $exe) } catch { $repRo = $false }
Assert $repRo 'B3 Ensure succeeded despite readonly'
Assert-HiddenLauncher 'B3' $cmdPath $vbsPath $lport
# clear any leftover readonly for later cases
try { (Get-Item $cmdPath).IsReadOnly = $false; (Get-Item $vbsPath).IsReadOnly = $false } catch {}
Assert-Clean 'B3'

Note 'B4: wipe .windows-mcp dir — Ensure recreates hidden launcher'
Stop-ListenersOnPort $lport
Start-Sleep -Milliseconds 300
# Keep a backup of auth/toml if present so we do not force long auth regen unless needed
$bak = Join-Path $env:TEMP ('wmcp-brutal-bak-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $bak | Out-Null
foreach ($n in @('auth.key', 'config.toml')) {
    $src = Join-Path $cfgDir $n
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $bak $n) -Force }
}
Remove-Item -LiteralPath $cfgDir -Recurse -Force -ErrorAction SilentlyContinue
Assert (-not (Test-Path -LiteralPath $cfgDir)) 'B4 cfg dir wiped'
$repWipe = $false
try { $repWipe = [bool](Ensure-WindowsMcpTask -WmExe $exe) } catch { $repWipe = $false }
Assert $repWipe 'B4 Ensure after wipe'
Assert (Test-Path -LiteralPath $cfgDir) 'B4 cfg dir recreated'
Assert-HiddenLauncher 'B4' $cmdPath $vbsPath $lport
# restore auth artifacts if we had them
foreach ($n in @('auth.key', 'config.toml')) {
    $src = Join-Path $bak $n
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $cfgDir $n) -Force }
}
Remove-Item -LiteralPath $bak -Recurse -Force -ErrorAction SilentlyContinue
Assert-Clean 'B4'

Note 'B5: empty WmExe must fail soft without destroying good launcher'
Assert-HiddenLauncher 'B5pre' $cmdPath $vbsPath $lport
$empty = $true
try { $empty = [bool](Ensure-WindowsMcpTask -WmExe '') } catch { $empty = $true }
Assert (-not $empty) 'B5 empty WmExe returns false'
Assert-HiddenLauncher 'B5post' $cmdPath $vbsPath $lport

Note 'B6: Start under Stop must NOT use vendor cmd even if planted'
Plant-VendorFlash $cmdPath $vbsPath
Stop-ListenersOnPort $lport
Start-Sleep -Milliseconds 400
$sw6 = [Diagnostics.Stopwatch]::StartNew()
$startOk = $false
try { $startOk = [bool](Start-WindowsMcpIfNeeded) } catch { $startOk = $false }
$sw6.Stop()
Assert $startOk 'B6 Start returned true with vendor cmd planted'
Assert (Wait-Listening 12) 'B6 listening via direct start'
Assert ($sw6.Elapsed.TotalSeconds -lt 20) ("B6 start <20s (got $([math]::Round($sw6.Elapsed.TotalSeconds,1))s)")
Assert-Clean 'B6'
# Start must not "fix" the planted cmd — Ensure does. Re-assert Start left no cmd flash.
# Repair for subsequent cases.
[void](Ensure-WindowsMcpTask -WmExe $exe)
Assert-HiddenLauncher 'B6repair' $cmdPath $vbsPath $lport

Note 'B7: Restart under Stop (schtasks /End stderr) + no /Run'
$sw7 = [Diagnostics.Stopwatch]::StartNew()
$reOk = $false
try { $reOk = [bool](Restart-WindowsMcpServer) } catch { $reOk = $false }
$sw7.Stop()
Assert $reOk 'B7 Restart under Stop returned true'
Assert (Wait-Listening 12) 'B7 listening after Restart'
Assert ($sw7.Elapsed.TotalSeconds -lt 25) ("B7 restart <25s (got $([math]::Round($sw7.Elapsed.TotalSeconds,1))s)")
Assert-Clean 'B7'

Note 'B8: plant-during-Ensure race (background plant vs Ensure x8)'
$raceScript = Join-Path $env:TEMP ('wmcp-brutal-plant-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
@'
param([string]$CmdPath,[string]$VbsPath,[int]$Seconds)
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
  try {
    Set-Content -LiteralPath $VbsPath -Value 'RACE_CORRUPT' -Encoding ASCII -Force
    Set-Content -LiteralPath $CmdPath -Value "@echo off`r`npython.exe -m windows_mcp serve --port 8000`r`n" -Encoding ASCII -Force
  } catch {}
  Start-Sleep -Milliseconds 120
}
'@ | Set-Content -LiteralPath $raceScript -Encoding UTF8
$plantProc = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $raceScript, '-CmdPath', $cmdPath, '-VbsPath', $vbsPath, '-Seconds', '14'
) -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 200
1..8 | ForEach-Object {
    try { [void](Ensure-WindowsMcpTask -WmExe (Get-WindowsMcpExe)) } catch {}
    try { [void](Start-WindowsMcpIfNeeded) } catch {}
    Start-Sleep -Milliseconds 150
}
$deadline = (Get-Date).AddSeconds(18)
while ((Get-Date) -lt $deadline -and -not $plantProc.HasExited) { Start-Sleep -Milliseconds 200 }
if (-not $plantProc.HasExited) { try { Stop-Process -Id $plantProc.Id -Force -EA SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 300
# Final Ensure wins the race
$final = $false
try { $final = [bool](Ensure-WindowsMcpTask -WmExe $exe) } catch { $final = $false }
Assert $final 'B8 final Ensure after race'
Assert-HiddenLauncher 'B8' $cmdPath $vbsPath $lport
Assert (Wait-Listening 12) 'B8 listening after race'
Assert-Clean 'B8'
Remove-Item -LiteralPath $raceScript -Force -ErrorAction SilentlyContinue

Note 'B9: Maintain under Stop + quiet (no throw, no flash)'
$mOk = $true
try {
    1..4 | ForEach-Object { [void](Maintain-WindowsMcpSession) }
} catch { $mOk = $false }
Assert $mOk 'B9 Maintain x4 under Stop no throw'
Assert (Wait-Listening 10) 'B9 still listening'
Assert-Clean 'B9'

Note 'B10: auth path under Stop — force CLI regen stderr must not kill Ensure-Task'
# Soft: call auth helper if key exists; if missing, regen. Never leave launcher broken.
$authPath = Join-Path $cfgDir 'auth.key'
$hadAuth = Test-Path -LiteralPath $authPath
$authBefore = $null
if ($hadAuth) { $authBefore = (Get-Content $authPath -Raw -ErrorAction SilentlyContinue) }
# Touch auth CLI under Stop (may stderr) — must not throw out of helper
$authThrew = $false
try {
    $k = Ensure-WindowsMcpAuth -WmExe $exe -CfgDir $cfgDir
    Assert ([bool]$k) 'B10 auth key present after Ensure-WindowsMcpAuth'
} catch {
    $authThrew = $true
}
Assert (-not $authThrew) 'B10 auth helper no throw under Stop'
# Ensure-Task still repairs if we plant after auth noise
Plant-VendorFlash $cmdPath $vbsPath
$afterAuth = $false
try { $afterAuth = [bool](Ensure-WindowsMcpTask -WmExe $exe) } catch { $afterAuth = $false }
Assert $afterAuth 'B10 Ensure-Task after auth still true'
Assert-HiddenLauncher 'B10' $cmdPath $vbsPath $lport
Assert-Clean 'B10'

Note 'B11: kill thrash x6 under Stop — Start recover, never cmd/schtasks Run'
$thrashOk = $true
1..6 | ForEach-Object {
    Stop-ListenersOnPort $lport
    Start-Sleep -Milliseconds 250
    $ok = $false
    try { $ok = [bool](Start-WindowsMcpIfNeeded) } catch { $ok = $false }
    if (-not $ok -and -not (Wait-Listening 10)) { $script:thrashOk = $false }
    if ((Get-WmcpCmdLeaks).Count -gt 0) { $script:thrashOk = $false }
    if ((Get-SchtasksRuns).Count -gt 0) { $script:thrashOk = $false }
}
Assert $thrashOk 'B11 thrash x6 all recover clean'
Assert (Wait-Listening 10) 'B11 final listening'

Note 'B12: HTTP + MainWindowHandle + dual-zero gate'
$serves = @(Get-CimInstance Win32_Process -Filter "Name='windows-mcp.exe'" -ErrorAction SilentlyContinue | Where-Object {
    ([string]$_.CommandLine) -match 'serve'
})
if ($serves.Count -eq 0) {
    $serves = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match 'windows_mcp') -and ($c -match 'serve')
    })
}
Assert ($serves.Count -ge 1) ("B12 serve procs >=1 (got $($serves.Count))")
$vis = @($serves | Where-Object {
    try { $p = Get-Process -Id $_.ProcessId -EA SilentlyContinue; $p -and $p.MainWindowHandle -ne [IntPtr]::Zero } catch { $false }
})
Assert ($vis.Count -eq 0) ("B12 MainWindowHandle all zero (visible=$($vis.Count))")
$hits = 0
1..5 | ForEach-Object { if (Test-LocalMcpHttp -Port $lport) { $script:hits++ }; Start-Sleep -Milliseconds 150 }
Assert ($hits -ge 3) ("B12 HTTP hits >=3/5 (got $hits)")
Assert-Clean 'B12'
Assert-HiddenLauncher 'B12final' $cmdPath $vbsPath $lport

Write-Host ''
if ($Fail -gt 0) {
    Write-Host "BRUTAL LIVE WINDOWS-MCP ABUSE: $Pass pass / $Fail fail" -ForegroundColor Red
    exit 1
}
Write-Host "BRUTAL LIVE WINDOWS-MCP ABUSE: $Pass pass / $Fail fail" -ForegroundColor Green
exit 0
