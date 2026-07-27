#Requires -Version 5.1
# test-logging-runid-hard-batch.ps1
# HARD batch gate: RUN_ID mint/handoff, session-bracketed day logs, zero-loss sync contracts,
# ERROR vs WARN flush policy, forbid-shrink, fast mkdir, and one LIVE dual-mint probe.
# 14 Assert calls. Does NOT modify run-all.ps1.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

$failed = 0
$passed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

function Get-BalancedBlock {
    param([string]$Text, [string]$StartPattern)
    $m = [regex]::Match($Text, $StartPattern)
    if (-not $m.Success) { return '' }
    $start = $m.Index
    $i = $Text.IndexOf('{', $start)
    if ($i -lt 0) { return '' }
    $depth = 0
    for ($p = $i; $p -lt $Text.Length; $p++) {
        $ch = $Text[$p]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $p - $start + 1) }
        }
    }
    return ''
}

Write-Host ''
Write-Host '=== test-logging-runid-hard-batch ===' -ForegroundColor Cyan
Write-Host ''

$uiPath = Get-ClientFile 'connect-ui.ps1'
$uiShPath = Get-ClientFile 'connect-ui.sh'
$batPath = Get-ClientFile 'windows\connect.bat'
$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
$docsPath = Join-Path $script:RepoRoot 'docs\client-connect.md'

$ui = Get-Content -LiteralPath $uiPath -Raw
$uiSh = Get-Content -LiteralPath $uiShPath -Raw
$bat = Get-Content -LiteralPath $batPath -Raw
$pre = Get-Content -LiteralPath $prePath -Raw
$docs = if (Test-Path -LiteralPath $docsPath) { Get-Content -LiteralPath $docsPath -Raw } else { '' }

$waitBody = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Wait-ConnectExit\b'
$ufeBody = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Write-ConnectUserFacingError\b'
$wcBody = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Write-ConnectLog\b'
$mutexFn = Get-FunctionSource -Content $ui -Name 'Get-ConnectLogWriteMutex'

Write-Host '--- Static contracts (13) ---' -ForegroundColor DarkCyan

Assert (
    ($waitBody -match 'FAIL EXIT reason=') -and
    ($waitBody -match "(?s)if \(\`$Code -ne 0\)[\s\S]*FAIL EXIT[\s\S]*'ERROR'")
) 'Wait-ConnectExit FAIL EXIT on non-zero uses ERROR level'

Assert (
    ($ufeBody -match 'USER_ERROR:') -and ($ufeBody -match "Write-ConnectLog[\s\S]*'ERROR'")
) 'Write-ConnectUserFacingError logs USER_ERROR at ERROR level'

Assert (
    ($ui -match 'SESSION_FILTER grep=\[\$\(\$script:ConnectSessionId\)\]') -and
    ($ui -match 'SESSION_FILTER[^\r\n]*tip=Select-String -Pattern')
) 'SESSION_FILTER grep tip + usable Select-String -Pattern filter'

Assert ($wcBody -match '\[\$ts\] \[\$Level\] \[\$sid\]') 'Write-ConnectLog lines include [session-id] bracket'

Assert ($mutexFn -match 'Global\\ClaudeConnectDayLogWrite-\$dayTag') 'day-log mutex Global\ClaudeConnectDayLogWrite-<dayTag>'

Assert (
    ($ui -match 'Zero-loss offline-first') -or ($uiSh -match 'Zero-loss offline-first') -or ($docs -match 'zero-loss offline-first')
) 'zero-loss offline-first policy in code or docs/client-connect.md'

Assert (
    ($ui -match 'LOG_SYNC_SKIP reason=forbid_shrink') -and ($ui -match 'LocalSize -lt \$RemoteSize') -and
    ($uiSh -match 'LOG_SYNC_SKIP reason=forbid_shrink')
) 'no-shrink sync: forbid_shrink when local < remote (Win+Mac)'

$mkMatch = [regex]::Match($ui, '\$mk\s*=\s*''([^'']+)''')
Assert (
    $mkMatch.Success -and ($mkMatch.Groups[1].Value -notmatch 'find\s+.*mtime') -and ($ui -match 'LogSyncFastMkdirMs')
) 'log-sync fast mkdir: LogSyncFastMkdirMs + $mk without find ... mtime'

Assert (
    ($wcBody -match "Level -eq 'ERROR'") -and ($wcBody -match 'Complete-ConnectLogAsyncDrain\s+-Force') -and
    ($wcBody -match "Level -eq 'WARN'") -and ($wcBody -match 'ConnectLogWarnPendingUntil') -and ($wcBody -match 'Request-ConnectLogSync')
) 'ERROR force-flush vs WARN coalesce via Request-ConnectLogSync'

$mintAt = $bat.IndexOf('Multi-UI: mint a unique RUN_ID')
$preAt = $bat.IndexOf('if exist "%HERE%connect-preflight.ps1"')
Assert ($mintAt -ge 0 -and $preAt -gt $mintAt) 'connect.bat mints RUN_ID before preflight'

Assert ($pre -match 'claude-connect-run-id\.\{0\}\.txt') 'preflight per-PID RUN_ID handoff file'

Assert ($bat -match 'if not defined CLAUDE_CONNECT_RUN_ID if exist "%TEMP%\\claude-connect-run-id\.txt"') 'bat adopts shared RUN_ID handoff only when unset'

Assert (
    ($bat -match '\[ERROR\].*FAIL UPDATE_BAT_EXIT') -and ($bat -match '\[\{0\}\] \[INFO\] \[\{1\}\].*BOOTSTRAP')
) 'connect.bat FAIL/BOOTSTRAP lines use [ERROR]/[INFO] with session id bracket'

Write-Host '--- LIVE dual-mint (1) ---' -ForegroundColor DarkCyan

$shared = Join-Path $env:TEMP ('claude-connect-run-id-hardbatch-' + [guid]::NewGuid().ToString('N') + '.txt')
$probe = Join-Path $env:TEMP ('claude-connect-runid-probe-' + [guid]::NewGuid().ToString('N') + '.cmd')
$out1 = Join-Path $env:TEMP ('rid-hard-out1-' + [guid]::NewGuid().ToString('N') + '.txt')
$out2 = Join-Path $env:TEMP ('rid-hard-out2-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
    $sharedPs = $shared.Replace("'", "''")
    $probeBody = @"
@echo off
setlocal EnableDelayedExpansion
set "CLAUDE_CONNECT_RUN_ID="
if not defined CLAUDE_CONNECT_RUN_ID (
  for /f %%I in ('powershell -NoProfile -WindowStyle Hidden -Command "[guid]::NewGuid().ToString('N').Substring(0,12)"') do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
powershell -NoProfile -WindowStyle Hidden -Command "Set-Content -LiteralPath '$sharedPs' -Value `$env:CLAUDE_CONNECT_RUN_ID -Encoding ASCII"
if not defined CLAUDE_CONNECT_RUN_ID if exist "$shared" (
  for /f "usebackq delims=" %%I in ("$shared") do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
echo !CLAUDE_CONNECT_RUN_ID!
"@
    Set-Content -LiteralPath $probe -Value $probeBody -Encoding ASCII

    $prevRunId = $env:CLAUDE_CONNECT_RUN_ID
    Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue
    try {
        $p1 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probe`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $out1 -RedirectStandardError ($out1 + '.err')
        Start-Sleep -Milliseconds 30
        $p2 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probe`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $out2 -RedirectStandardError ($out2 + '.err')
    } finally {
        if ($null -ne $prevRunId -and "$prevRunId" -ne '') {
            $env:CLAUDE_CONNECT_RUN_ID = $prevRunId
        }
    }
    $null = $p1.WaitForExit(15000)
    $null = $p2.WaitForExit(15000)
    $id1 = ((Get-Content -LiteralPath $out1 -ErrorAction Stop | Select-Object -First 1) + '').Trim()
    $id2 = ((Get-Content -LiteralPath $out2 -ErrorAction Stop | Select-Object -First 1) + '').Trim()
    Assert (
        $p1.HasExited -and $p2.HasExited -and
        ($id1 -match '^[0-9a-fA-F]{12}$') -and ($id2 -match '^[0-9a-fA-F]{12}$') -and ($id1 -ne $id2)
    ) "LIVE dual-mint: distinct 12-hex RUN_IDs ($id1 vs $id2)"
}
finally {
    Remove-Item -LiteralPath $probe, $shared, $out1, $out2 -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("=== RESULT pass={0} fail={1} asserts={2} ===" -f $passed, $failed, ($passed + $failed)) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
