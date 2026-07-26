#Requires -Version 5.1
# test-connect-preflight-skip-heal.ps1
# Task 2: after preflight heal exits 0, set CLAUDE_CONNECT_SKIP_HEAL so connect.ps1 skips duplicate heal.
# Exit 2 (redirect) must not set SKIP_HEAL; missing healPath must not force-skip.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Get-HealBlock([string]$Content) {
    $start = $Content.IndexOf('$skipHealFromHandoff')
    if ($start -lt 0) { $start = $Content.IndexOf('$healPath = Join-Path') }
    if ($start -lt 0) { return $null }
    $updateStart = $Content.IndexOf('$isSepidz =', $start)
    if ($updateStart -lt 0) { return $Content.Substring($start) }
    return $Content.Substring($start, $updateStart - $start)
}

function New-StubHealScript {
    param([int]$ExitCode, [string]$Dir)
    $path = Join-Path $Dir 'connect-heal.ps1'
    @"
param([string]`$Here, [switch]`$Quiet)
exit $ExitCode
"@ | Set-Content -LiteralPath $path -Encoding ASCII
    return $path
}

function Invoke-PreflightInProcess {
    param(
        [string]$Here,
        [scriptblock]$InvokePreflightScriptOverride
    )

    $prePath = Get-ClientFile 'windows\connect-preflight.ps1'
    $pre = Get-Content -LiteralPath $prePath -Raw

    $helperStart = $pre.IndexOf('function ConvertTo-ProcessArgument')
    $healBlockStart = $pre.IndexOf('$skipHealFromHandoff')
    if ($healBlockStart -lt 0) { $healBlockStart = $pre.IndexOf('$healPath = Join-Path') }
    $fnEnd = if ($healBlockStart -ge 0) { $healBlockStart } else { $pre.IndexOf('if ($env:CLAUDE_CONNECT_RUN_ID') }
    if ($helperStart -lt 0 -or $fnEnd -le $helperStart) { throw 'Could not extract preflight helpers from connect-preflight.ps1' }
    $helpers = $pre.Substring($helperStart, $fnEnd - $helperStart)

    $healBlock = Get-HealBlock $pre
    if (-not $healBlock) { throw 'Could not extract heal block from connect-preflight.ps1' }

    $preHandoff = @'
$handoff = @{}
$PreflightHandoff = Join-Path $env:TEMP 'claude-connect-preflight.ok'
function Read-PreflightHandoff { return @{} }
function Test-HealthyDeploy { param([string]$Dir) return $true }
'@

    $script = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$Here = '$($Here -replace "'", "''")'
$helpers
$preHandoff
function Invoke-PreflightScript {
    param(
        [Parameter(Mandatory = `$true)][string]`$Path,
        [string[]]`$Arguments = @(),
        [switch]`$Sta
    )
    return (& {
$($InvokePreflightScriptOverride.ToString())
    })
}
$healBlock
"@
    Invoke-Expression $script
}

Write-Host ''
Write-Host '=== connect-preflight SKIP_HEAL after heal success ===' -ForegroundColor Cyan

$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
Assert (Test-Path -LiteralPath $prePath) 'connect-preflight.ps1 exists'
$pre = Get-Content -LiteralPath $prePath -Raw
$healBlock = Get-HealBlock $pre
Assert ($null -ne $healBlock) 'heal block extracted from connect-preflight.ps1'

Write-Host ''
Write-Host '--- Source contracts ---' -ForegroundColor DarkCyan

Assert ($healBlock -match '\$healExit = Invoke-PreflightScript') 'heal invokes Invoke-PreflightScript'
Assert ($healBlock -match 'if \(\$healExit -eq 2\) \{ exit 2 \}') 'heal exit 2 triggers preflight exit 2'

$exit2At = $healBlock.IndexOf('if ($healExit -eq 2)')
$skipAssignAt = $healBlock.IndexOf('$env:CLAUDE_CONNECT_SKIP_HEAL = ''1''')
Assert ($skipAssignAt -gt 0) 'heal block sets CLAUDE_CONNECT_SKIP_HEAL after successful heal'
Assert ($exit2At -ge 0 -and $skipAssignAt -gt $exit2At) 'SKIP_HEAL assignment comes after exit-2 guard'

Assert ($healBlock -match 'if \(\$healExit -eq 0\)') 'SKIP_HEAL gated on heal exit 0'
Assert ($healBlock -match '\$env:CLAUDE_CONNECT_SKIP_HEAL\s*=\s*''1''') 'SKIP_HEAL set to literal 1'
Assert ($healBlock -match 'if \(\$healExit -eq 0\) \{[\s\S]*?\$env:CLAUDE_CONNECT_SKIP_HEAL\s*=\s*''1''') 'SKIP_HEAL assignment nested under heal exit 0'

Assert ($healBlock -match '-not \$skipHealFromHandoff') 'heal skips when bootstrap handoff says healthy current'
Assert ($healBlock -match '\$env:CLAUDE_CONNECT_SKIP_HEAL -ne ''1''') 'heal runs only when SKIP_HEAL unset'
Assert ($healBlock -match 'Test-Path -LiteralPath \$healPath') 'heal requires healPath exists'
Assert ($healBlock -match 'skipHealFromHandoff|SKIP_HEAL') 'heal block respects bootstrap handoff SKIP_HEAL'

Write-Host ''
Write-Host '--- connect.bat preflight handoff ---' -ForegroundColor DarkCyan

$batPath = Get-ClientFile 'windows\connect.bat'
Assert (Test-Path -LiteralPath $batPath) 'connect.bat exists'
$bat = Get-Content -LiteralPath $batPath -Raw

$preflightStart = $bat.IndexOf('if exist "%HERE%connect-preflight.ps1"')
Assert ($preflightStart -ge 0) 'connect.bat has preflight block'

$preflightEnd = $bat.IndexOf('REM Stable run id:', $preflightStart)
if ($preflightEnd -lt 0) { $preflightEnd = $bat.IndexOf('if not defined CLAUDE_CONNECT_RUN_ID', $preflightStart) }
Assert ($preflightEnd -gt $preflightStart) 'connect.bat preflight block bounded'

$preflightBlock = $bat.Substring($preflightStart, $preflightEnd - $preflightStart)
Assert ($preflightBlock -match 'set "CLAUDE_CONNECT_SKIP_HEAL=1"') 'preflight happy path sets SKIP_HEAL in bat'
Assert ($preflightBlock -match 'claude-connect-preflight\.ok') 'bat reads bootstrap preflight handoff file'
Assert ($preflightBlock -match 'set "CLAUDE_CONNECT_SKIP_BOOTSTRAP=1"') 'preflight happy path sets SKIP_BOOTSTRAP in bat'

$preEcSet = $preflightBlock.IndexOf('set "PRE_EC=!errorlevel!"')
$handoffRead = $preflightBlock.IndexOf('claude-connect-preflight.ok')
$exit3At = $preflightBlock.IndexOf('if "!PRE_EC!"=="3"')
$skipHealAt = $preflightBlock.IndexOf('set "CLAUDE_CONNECT_SKIP_HEAL=1"')
$afterUpdateGoto = $preflightBlock.IndexOf('goto AFTER_CLIENT_UPDATE', $skipHealAt)
Assert ($preEcSet -ge 0 -and $handoffRead -gt $preEcSet) 'bat reads preflight handoff after preflight exit code'
Assert ($handoffRead -gt 0 -and $exit3At -gt $handoffRead) 'handoff read before exit-3 relaunch branch'
Assert ($skipHealAt -gt 0 -and $afterUpdateGoto -gt $skipHealAt) 'SKIP_HEAL set before goto AFTER_CLIENT_UPDATE on happy path'

$bootStart = $bat.IndexOf('start "" /D "%HERE_NOTRAIL%" powershell')
$happyGotoAbs = $preflightStart + $afterUpdateGoto
Assert ($bootStart -gt $happyGotoAbs) 'preflight skip flags precede connect-boot handoff'

Write-Host ''
Write-Host '--- Runtime stubs (in-process heal block) ---' -ForegroundColor DarkCyan

$tmp = Join-Path $env:TEMP ('preflight-skip-heal-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    New-StubHealScript -ExitCode 0 -Dir $tmp | Out-Null

    Remove-Item Env:CLAUDE_CONNECT_SKIP_HEAL -ErrorAction SilentlyContinue
    Invoke-PreflightInProcess -Here $tmp -InvokePreflightScriptOverride { return 0 }
    Assert ($env:CLAUDE_CONNECT_SKIP_HEAL -eq '1') 'heal exit 0 sets SKIP_HEAL in-process'

    Remove-Item Env:CLAUDE_CONNECT_SKIP_HEAL -ErrorAction SilentlyContinue
    $exit2Dir = Join-Path $tmp 'exit2'
    New-Item -ItemType Directory -Force -Path $exit2Dir | Out-Null
    New-StubHealScript -ExitCode 2 -Dir $exit2Dir | Out-Null
    $exit2Proc = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $prePath,
        '-Here', $exit2Dir
    ) -Wait -PassThru -WindowStyle Hidden
    Assert ($exit2Proc.ExitCode -eq 2) 'heal exit 2 propagates preflight exit 2'
    Assert ($null -eq $env:CLAUDE_CONNECT_SKIP_HEAL) 'parent env unchanged after child heal exit 2'

    Remove-Item Env:CLAUDE_CONNECT_SKIP_HEAL -ErrorAction SilentlyContinue
    $env:CLAUDE_CONNECT_SKIP_HEAL = '1'
    Invoke-PreflightInProcess -Here $tmp -InvokePreflightScriptOverride { throw 'heal must not run when SKIP_HEAL already 1' }
    Assert ($env:CLAUDE_CONNECT_SKIP_HEAL -eq '1') 'pre-set SKIP_HEAL left unchanged when heal skipped'

    Remove-Item Env:CLAUDE_CONNECT_SKIP_HEAL -ErrorAction SilentlyContinue
    $noHealDir = Join-Path $tmp 'no-heal'
    New-Item -ItemType Directory -Force -Path $noHealDir | Out-Null
    Invoke-PreflightInProcess -Here $noHealDir -InvokePreflightScriptOverride { throw 'heal must not run when healPath missing' }
    Assert ($null -eq $env:CLAUDE_CONNECT_SKIP_HEAL) 'missing healPath does not set SKIP_HEAL'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_SKIP_HEAL -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All connect-preflight skip-heal tests passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail test(s) failed." -ForegroundColor Red
exit 1
