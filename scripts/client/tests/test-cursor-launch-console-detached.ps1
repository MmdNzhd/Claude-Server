#Requires -Version 5.1
# RED contracts: Cursor/editor launch must isolate Electron console from the connect parent.
# Start-EditorProcessDirect must set ELECTRON_NO_ATTACH_CONSOLE, redirect stdio to cursor-launch
# day logs, AND hard-detach (DETACHED_PROCESS / CREATE_NEW_PROCESS_GROUP or equivalent).
# Elevated NonElevatedLauncher CreateProcessWithTokenW must pass non-zero detach creationFlags.
# Today Direct uses Start-Process -Redirect* only (no detach flags) — this test must FAIL until GREEN.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

function Test-HasHardDetach([string]$Src) {
    if ([string]::IsNullOrWhiteSpace($Src)) { return $false }
    # Detectable hard-detach contracts (any one is enough for GREEN):
    # DETACHED_PROCESS = 0x00000008; CREATE_NEW_PROCESS_GROUP = 0x00000200
    if ($Src -match 'DETACHED_PROCESS') { return $true }
    if ($Src -match 'CREATE_NEW_PROCESS_GROUP') { return $true }
    if ($Src -match '0x00000008') { return $true }
    if ($Src -match '0x8\b') { return $true }
    if ($Src -match '0x00000200') { return $true }
    # ProcessStartInfo.CreationFlags / dwCreationFlags with detach bit OR'd in
    if ($Src -match '(?i)CreationFlags\s*[|=]') { return $true }
    if ($Src -match '(?i)dwCreationFlags\s*[|=]') { return $true }
    return $false
}

Write-Host ''
Write-Host '=== Cursor launch console detach (source contracts) ===' -ForegroundColor White

$elPath = Get-ClientFile 'editor-launch.ps1'
Assert (Test-Path -LiteralPath $elPath) "editor-launch.ps1 exists ($elPath)"
$el = Get-Content -LiteralPath $elPath -Raw

$direct = Get-FunctionSource -Content $el -Name 'Start-EditorProcessDirect'
Assert (-not [string]::IsNullOrWhiteSpace($direct)) 'Start-EditorProcessDirect extractable via Get-FunctionSource'

if ($direct) {
    Assert ($direct -match 'ELECTRON_NO_ATTACH_CONSOLE') `
        'Start-EditorProcessDirect sets ELECTRON_NO_ATTACH_CONSOLE'

    $redirOut = $direct -match 'RedirectStandardOutput'
    $redirErr = $direct -match 'RedirectStandardError'
    Assert ($redirOut -and $redirErr) `
        'Start-EditorProcessDirect redirects stdout+stderr (RedirectStandardOutput/Error)'

    $toDayLog = ($direct -match 'Get-CursorLaunchDayLogPath') -or `
        ($direct -match 'cursor-launch-') -or `
        ($direct -match 'cursor-launch-\{0\}')
    Assert $toDayLog `
        'Start-EditorProcessDirect redirect targets cursor-launch day logs'

    $directDetach = Test-HasHardDetach $direct
    Assert $directDetach `
        'Start-EditorProcessDirect hard-detaches (DETACHED_PROCESS 0x8 and/or CREATE_NEW_PROCESS_GROUP) — Redirect* alone is not enough'
    if (-not $directDetach) {
        Write-Host '  note  Direct uses Start-Process -Redirect* without DETACHED_PROCESS / CREATE_NEW_PROCESS_GROUP' -ForegroundColor DarkYellow
    }
}

# Elevated path: NonElevatedLauncher -> CreateProcessWithTokenW (C# Add-Type block)
Assert ($el -match 'CreateProcessWithTokenW') 'NonElevatedLauncher CreateProcessWithTokenW present'
Assert ($el -match 'class\s+NonElevatedLauncher') 'NonElevatedLauncher type present'

$nelMatch = [regex]::Match($el, '(?s)public static class NonElevatedLauncher\s*\{.*?^\}\s*''@', [System.Text.RegularExpressions.RegexOptions]::Multiline)
$nelSrc = if ($nelMatch.Success) { $nelMatch.Value } else {
    # Fallback: window around CreateProcessWithTokenW call site
    $idx = $el.IndexOf('CreateProcessWithTokenW(')
    if ($idx -ge 0) {
        $start = [Math]::Max(0, $idx - 400)
        $el.Substring($start, [Math]::Min(900, $el.Length - $start))
    } else { '' }
}
Assert (-not [string]::IsNullOrWhiteSpace($nelSrc)) 'NonElevatedLauncher source extractable'

if ($nelSrc) {
    # creationFlags arg today is literal 0 — must become detach flags for Cursor isolation
    $callZero = [regex]::IsMatch($nelSrc, 'CreateProcessWithTokenW\s*\([^;]*?,\s*0\s*,')
    $nelDetach = Test-HasHardDetach $nelSrc
    # Pass only if detach flags are present AND the call is not hard-coded to creationFlags=0
    Assert (($nelDetach) -and (-not $callZero)) `
        'NonElevatedLauncher CreateProcessWithTokenW must use DETACHED_PROCESS / CREATE_NEW_PROCESS_GROUP (creationFlags != 0)'
    if ($callZero) {
        Write-Host '  note  CreateProcessWithTokenW(..., 0, ...) — creationFlags=0 (no hard detach)' -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host ("Result: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -eq 0) { exit 0 }
exit 1
