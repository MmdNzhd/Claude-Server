#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
Write-Host "ROOT=$(Get-Location)"

function Set-FileText([string]$Rel, [string]$Old, [string]$New, [string]$Label) {
    $path = Resolve-Path $Rel
    $text = [IO.File]::ReadAllText($path)
    if ($text -notlike "*$($Old.Substring(0, [Math]::Min(40, $Old.Length)))*") {
        # fallback: check contains exact
    }
    if (-not $text.Contains($Old)) {
        Write-Host "SKIP/MISS $Label — old snippet not found" -ForegroundColor Yellow
        return $false
    }
    $text2 = $text.Replace($Old, $New)
    if ($text2 -eq $text) {
        Write-Host "NOOP $Label" -ForegroundColor Yellow
        return $false
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($path, $text2, $utf8)
    Write-Host "OK $Label" -ForegroundColor Green
    return $true
}

# --- 1) TunnelPid param in git-mode.ps1 ---
$gm = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/git-mode.ps1'))
$gm2 = $gm
# Only in Write-TunnelDropLog param block — replace [int]$Pid = 0 with TunnelPid
$gm2 = [regex]::Replace($gm2, '(function Write-TunnelDropLog\s*\{[\s\S]*?param\([\s\S]*?)\[int\]\$Pid\s*=\s*0', '${1}[int]$TunnelPid = 0', 1)
$gm2 = [regex]::Replace($gm2, '(if \(\$Pid -gt 0\) \{ \$parts \+= "bg_pid=\$Pid" \})', 'if ($TunnelPid -gt 0) { $parts += "bg_pid=$TunnelPid" }', 1)
# Also catch if already mixed
$gm2 = $gm2.Replace('if ($Pid -gt 0) { $parts += "bg_pid=$Pid" }', 'if ($TunnelPid -gt 0) { $parts += "bg_pid=$TunnelPid" }')
if ($gm2 -eq $gm) {
    Write-Host 'WARN git-mode TunnelPid replace may have partially applied or already done' -ForegroundColor Yellow
    # show current param line
    if ($gm -match '\[int\]\$Pid\s*=\s*0') { Write-Host 'STILL HAS [int]$Pid' -ForegroundColor Red }
    if ($gm -match '\[int\]\$TunnelPid') { Write-Host 'HAS TunnelPid already' -ForegroundColor Green }
} else {
    [IO.File]::WriteAllText((Resolve-Path 'scripts/client/git-mode.ps1'), $gm2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'OK git-mode Write-TunnelDropLog -> TunnelPid' -ForegroundColor Green
}

# --- 2) connect.ps1 -Pid -> -TunnelPid ---
$win = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/windows/connect.ps1'))
$win2 = $win.Replace('-RecoveryGen $script:RecoveryGeneration -Pid $bgPid', '-RecoveryGen $script:RecoveryGeneration -TunnelPid $bgPid')
if ($win2 -eq $win) {
    if ($win -match '-TunnelPid \$bgPid') { Write-Host 'OK connect.ps1 already -TunnelPid' -ForegroundColor Green }
    else { Write-Host 'MISS connect.ps1 -Pid call site' -ForegroundColor Red }
} else {
    [IO.File]::WriteAllText((Resolve-Path 'scripts/client/windows/connect.ps1'), $win2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'OK connect.ps1 -TunnelPid' -ForegroundColor Green
}

# --- 3) editor-launch fail-closed ---
$el = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/editor-launch.ps1'))
$oldWarn = @'
    Write-EditorLaunchLog 'LAUNCH_WARN: process started but folder workspace not detected - press O to retry' 'WARN'
    Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=warn'
    return $true
}
'@
# try flexible match near end of Launch-RemoteEditor
if ($el -match "(?s)(Write-EditorLaunchLog 'LAUNCH_WARN: process started but folder workspace not detected - press O to retry' 'WARN'\r?\n\s*Write-LaunchPerfLog -Mark 'launch_total' -Ms \$script:LaunchPerfSw\.ElapsedMilliseconds -Extra 'path=warn'\r?\n\s*return \$true)") {
    $el2 = $el -replace "(?s)Write-EditorLaunchLog 'LAUNCH_WARN: process started but folder workspace not detected - press O to retry' 'WARN'\r?\n\s*Write-LaunchPerfLog -Mark 'launch_total' -Ms \$script:LaunchPerfSw\.ElapsedMilliseconds -Extra 'path=warn'\r?\n\s*return \$true", @'
Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process (or folder not detected) - press O to retry' 'ERROR'
    Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_window'
    return $false
'@
    [IO.File]::WriteAllText((Resolve-Path 'scripts/client/editor-launch.ps1'), $el2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'OK editor-launch return false on exhaust' -ForegroundColor Green
} else {
    Write-Host 'MISS LAUNCH_WARN return true block — dumping nearby' -ForegroundColor Yellow
    $idx = $el.IndexOf('LAUNCH_WARN: process started but folder workspace not detected')
    if ($idx -ge 0) { Write-Host $el.Substring($idx, [Math]::Min(350, $el.Length-$idx)) }
}

# Also harden Start-ProcessAsInteractiveUser launch task OK only with process
$el = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/editor-launch.ps1'))
if ($el -notmatch 'PROC_START_FAIL: mode=elevated_launch_task') {
    $oldFallback = @'
    $fallback = Start-ProcessViaLaunchTask -FilePath $FilePath -ArgumentList $ArgumentList
    Write-EditorLaunchLog "PROC_START_OK: mode=elevated_launch_task result=$fallback" 'DEBUG'
    return $fallback
}
'@
    $newFallback = @'
    $fallback = Start-ProcessViaLaunchTask -FilePath $FilePath -ArgumentList $ArgumentList
    if (-not $fallback) {
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task result=False' 'ERROR'
        return $false
    }
    # schtasks /Run exit 0 != process started — verify briefly
    $exeName = [IO.Path]::GetFileNameWithoutExtension($FilePath)
    $saw = $false
    for ($i = 0; $i -lt 4; $i++) {
        Start-Sleep -Milliseconds 400
        try {
            if (Get-Process -Name $exeName -ErrorAction SilentlyContinue) { $saw = $true; break }
        } catch { }
    }
    if (-not $saw) {
        Write-EditorLaunchLog "PROC_START_FAIL: mode=elevated_launch_task no_process exe=$exeName" 'ERROR'
        return $false
    }
    Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_launch_task' 'DEBUG'
    return $true
}
'@
    if ($el.Contains($oldFallback)) {
        $el = $el.Replace($oldFallback, $newFallback)
        [IO.File]::WriteAllText((Resolve-Path 'scripts/client/editor-launch.ps1'), $el, (New-Object System.Text.UTF8Encoding $false))
        Write-Host 'OK elevated_launch_task process evidence gate' -ForegroundColor Green
    } else {
        Write-Host 'MISS elevated fallback block exact text' -ForegroundColor Yellow
        $idx = $el.IndexOf('elevated_launch_task')
        if ($idx -ge 0) { Write-Host $el.Substring([Math]::Max(0,$idx-120), 300) }
    }
}

# --- 4) Invert hard-multi section A ---
$hardPath = Resolve-Path 'scripts/client/tests/test-hard-multi-agent-regressions.ps1'
$hard = [IO.File]::ReadAllText($hardPath)
$oldA = @'
Write-Host '--- A) Unlimited concurrent clients ---' -ForegroundColor Cyan
Assert ($ui -match 'MULTI_INSTANCE: allowed') 'Win: Enter-ConnectSingleInstance is multi-instance no-op'
Assert ($ui -notmatch 'Another Claude Connect is already running') 'Win: no blocking single-instance user message'
Assert ($ui -match '(?s)function Enter-ConnectSingleInstance.*?return \$true') 'Win: Enter-ConnectSingleInstance always returns true'
Assert ($ui -notmatch 'New-Object System\.Threading\.Mutex') 'Win: connect-ui does not take Global\\ClaudeConnect mutex'
Assert ($uiSh -match 'MULTI_INSTANCE: allowed') 'Mac: enter_connect_single_instance is multi-instance no-op'
Assert ($uiSh -notmatch 'Another Claude Connect is already running') 'Mac: no blocking flock user message'
Assert ($desPs -notmatch 'Designer \+ main connect cannot share') 'Designer Win: no dual-connect block message'
Assert ($desSh -notmatch 'exec 9>"\$_designer_lockfile"') 'Designer Mac: no connect.lock flock'
Assert ($gm -match '0\.\.9') 'Tunnel slots 0..9 exist for concurrent tunnels'
'@
$newA = @'
Write-Host '--- A) Single Connect UI per PC ---' -ForegroundColor Cyan
Assert ($ui -match 'Global\\ClaudeConnect') 'Win: Enter-ConnectSingleInstance takes Global\ClaudeConnect mutex'
Assert ($ui -match 'Another Claude Connect is already running') 'Win: blocking single-instance user message'
Assert ($ui -match 'SINGLE_INSTANCE') 'Win: SINGLE_INSTANCE log markers'
Assert ($ui -notmatch 'MULTI_INSTANCE: allowed') 'Win: MULTI_INSTANCE allowed removed'
Assert ($ui -match 'New-Object System\.Threading\.Mutex') 'Win: connect-ui uses Mutex'
Assert ($uiSh -notmatch 'MULTI_INSTANCE: allowed') 'Mac: MULTI_INSTANCE allowed removed'
Assert ($uiSh -match 'SINGLE_INSTANCE|flock|connect\.lock') 'Mac: single-instance flock/lock'
Assert ($gm -match '0\.\.9') 'Tunnel slots 0..9 remain for reconnect/slot picking'
Assert ($gm -match 'skip_peer_live|ACQUIRE_SKIP') 'Tunnel acquire skips peer-live ssh -R'
'@
if ($hard.Contains("Unlimited concurrent clients")) {
    # replace line-by-line more reliably with regex
    $hard2 = [regex]::Replace($hard, "(?s)Write-Host '--- A\) Unlimited concurrent clients ---'.*?(?=Write-Host '--- B\))", ($newA.TrimEnd() + "`r`n`r`n"), 1)
    if ($hard2 -eq $hard) {
        $hard2 = [regex]::Replace($hard, "(?s)Write-Host '--- A\) Unlimited concurrent clients ---'.*?(?=Write-Host '--- B\))", ($newA.TrimEnd() + "`n`n"), 1)
    }
    [IO.File]::WriteAllText($hardPath, $hard2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'OK hard-multi section A inverted' -ForegroundColor Green
} else {
    Write-Host 'SKIP hard-multi A already changed?' -ForegroundColor Yellow
}

# --- 5) session-log-contracts MULTI_INSTANCE ---
$slPath = Resolve-Path 'scripts/client/tests/test-session-log-contracts.ps1'
$sl = [IO.File]::ReadAllText($slPath)
$sl2 = $sl -replace "Assert \(\`$ui -match 'MULTI_INSTANCE: allowed'\) 'multi-instance allowed \(no global mutex\)'", "Assert (`$ui -match 'SINGLE_INSTANCE|Global\\\\ClaudeConnect') 'single-instance mutex (Global\\ClaudeConnect)'"
$sl2 = $sl2 -replace "Assert \(\`$ui -match 'MULTI_INSTANCE: allowed'\) `"multi-instance allowed \(no global mutex\)`"", "Assert (`$ui -match 'SINGLE_INSTANCE') 'single-instance'"
if ($sl2 -ne $sl) {
    [IO.File]::WriteAllText($slPath, $sl2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'OK session-log-contracts single-instance' -ForegroundColor Green
} else {
    Write-Host 'CHECK session-log-contracts manually' -ForegroundColor Yellow
    Select-String -Path $slPath -Pattern 'MULTI_INSTANCE|single-instance|SINGLE_INSTANCE' | ForEach-Object { Write-Host $_.Line }
}

# --- 6) pipeline 3x retry assert -> fail-fast ---
$pipePath = Resolve-Path 'scripts/client/tests/test-connect-pipeline.ps1'
$pipe = [IO.File]::ReadAllText($pipePath)
$pipe2 = $pipe -replace "Assert \(\`$mount -match 'while \(\\\`$n -lt 3\)'|Assert \(\`$[^)]+retries git rename 3x\)", ''
# find the exact assert
Select-String -Path $pipePath -Pattern '3x|lt 3|rename' | ForEach-Object { Write-Host ("PIPE:{0}:{1}" -f $_.LineNumber, $_.Line.Trim()) }
$pipe2 = [regex]::Replace($pipe, "Assert \([^\n]*retries git rename 3x[^\n]*\r?\n", "Assert (`$mount -match 'while \`\`\$n -lt 2|n -lt 2') 'claude-mount git hide fail-fast (<=2 attempts)'`r`n")
# simpler: replace message
if ($pipe -match "retries git rename 3x") {
    $pipe2 = $pipe.Replace("retries git rename 3x", "git hide fail-fast retries")
    # also fix the match pattern if it looks for lt 3
    $pipe2 = $pipe2 -replace "\`\$n -lt 3", '\$n -lt 2'
    $pipe2 = $pipe2 -replace '\$n -lt 3', '$n -lt 2'
    [IO.File]::WriteAllText($pipePath, $pipe2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'OK pipeline hide retry assert updated' -ForegroundColor Green
} else {
    Write-Host 'PIPE assert pattern not found as expected' -ForegroundColor Yellow
}

Write-Host "`nDone apply remainders." -ForegroundColor Cyan
