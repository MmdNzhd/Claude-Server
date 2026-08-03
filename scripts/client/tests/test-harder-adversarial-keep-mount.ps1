#Requires -Version 5.1
# test-harder-adversarial-keep-mount.ps1 (L6)
# Adversarial static/LIVE-light: AUTO_RECLAIM=0; Get drops dead tunnelPid; Write fail-open try/catch.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARDER L6: adversarial keep-mount (AUTO_RECLAIM / dead pid / write fail-open) ===' -ForegroundColor Cyan

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$reclaimSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectOrphanReclaim'
$getSrc = Get-FunctionSource -Content $gm -Name 'Get-ConnectKeepTunnelMarkers'
$writeSrc = Get-FunctionSource -Content $gm -Name 'Write-ConnectKeepTunnelMarker'

Assert ([bool]$reclaimSrc) 'extracted Invoke-ConnectOrphanReclaim'
Assert ([bool]$getSrc) 'extracted Get-ConnectKeepTunnelMarkers'
Assert ([bool]$writeSrc) 'extracted Write-ConnectKeepTunnelMarker'

# AUTO_RECLAIM=0
Assert ($reclaimSrc -match "CLAUDE_CONNECT_AUTO_RECLAIM") 'Reclaim reads CLAUDE_CONNECT_AUTO_RECLAIM'
Assert ($reclaimSrc -match "=\s*'0'|AUTO_RECLAIM=0") 'AUTO_RECLAIM=0 early return'
Assert ($reclaimSrc -match 'RECLAIM_SKIP reason=AUTO_RECLAIM=0') 'logs RECLAIM_SKIP on killswitch'
Assert ($reclaimSrc -match '(?s)AUTO_RECLAIM=0[\s\S]{0,200}return \$result') `
    'AUTO_RECLAIM=0 returns empty result (no kill)'

# Get drops dead tunnelPid
Assert ($getSrc -match 'dead_tunnelPid|reason=dead_tunnelPid') 'Get drops dead tunnelPid markers'
Assert ($getSrc -match 'Get-Process -Id \$tunnelPid') 'Get checks tunnelPid process liveness'
Assert ($getSrc -match 'Remove-Item') 'Get removes dead marker file'
Assert ($getSrc -match 'KEEP_MARKER_CLEAR') 'Get logs KEEP_MARKER_CLEAR on dead pid'

# Write fail-open try/catch (never throws to caller)
Assert ($writeSrc -match '(?s)try\s*\{[\s\S]*WriteAllText[\s\S]*\}\s*catch') `
    'Write-ConnectKeepTunnelMarker wrapped in try/catch'
Assert ($writeSrc -match 'KEEP_MARKER_WRITE_FAIL') 'Write fail-open logs KEEP_MARKER_WRITE_FAIL'
# Outer catch logs FAIL and does not rethrow (inner Replace fallback may throw into outer)
$outerCatch = [regex]::Match($writeSrc, '(?s)KEEP_MARKER_WRITE_FAIL.*')
Assert ($outerCatch.Success -and ($outerCatch.Value -notmatch '\bthrow\b')) `
    'Write outer catch is fail-open (KEEP_MARKER_WRITE_FAIL, no throw)'

# Optional LIVE: dead-pid drop against temp marker dir
$tmp = Join-Path $env:TEMP ("cc-l6-keep-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:CfgDir = $tmp
    function Get-ConnectSessionSlotMarkerDir { return [string]$script:CfgDir }
    function Write-GitModeLog { param([string]$Message, [string]$Level = 'INFO') }

    . ([scriptblock]::Create($getSrc))
    $deadPid = 1
    while (Get-Process -Id $deadPid -ErrorAction SilentlyContinue) { $deadPid++ }
    # Ensure deadPid truly dead
    if (Get-Process -Id $deadPid -ErrorAction SilentlyContinue) {
        $Skip++
        Write-Host '  SKIP  could not find a guaranteed-dead PID for LIVE drop' -ForegroundColor Yellow
    } else {
        $marker = Join-Path $tmp 'keep-tunnel-47001.json'
        $json = '{"port":47001,"slot":1,"tunnelPid":' + $deadPid + ',"projectId":"l6","remotePath":"/x/l6","alias":"","editorCmd":"","keptAt":"' + (Get-Date).ToString('o') + '"}'
        [System.IO.File]::WriteAllText($marker, $json, [System.Text.UTF8Encoding]::new($false))
        $got = @(Get-ConnectKeepTunnelMarkers)
        Assert ($got.Count -eq 0) 'LIVE Get drops marker with dead tunnelPid'
        Assert (-not (Test-Path -LiteralPath $marker)) 'LIVE Get removed dead-tunnel marker file'
    }

    # AUTO_RECLAIM=0 LIVE call
    . ([scriptblock]::Create((Get-FunctionSource -Content $gm -Name 'Invoke-ConnectOrphanReclaim')))
    function Get-TunnelPortUserBase { param([string]$UidStr) return 47000 }
    function Get-LocalTunnelSshPids { param([int]$TargetPort) return @(999999) }
    $prev = $env:CLAUDE_CONNECT_AUTO_RECLAIM
    $env:CLAUDE_CONNECT_AUTO_RECLAIM = '0'
    try {
        $r = Invoke-ConnectOrphanReclaim -UidStr '1000' -PreferredPort 47001
        Assert ($r.Killed -eq 0) 'LIVE AUTO_RECLAIM=0 kills nothing'
    } finally {
        if ($null -eq $prev) { Remove-Item Env:\CLAUDE_CONNECT_AUTO_RECLAIM -ErrorAction SilentlyContinue }
        else { $env:CLAUDE_CONNECT_AUTO_RECLAIM = $prev }
    }
} catch {
    Write-Host ("  FAIL  L6 LIVE stub: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L6 adversarial-keep-mount RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
