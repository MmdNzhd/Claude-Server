#Requires -Version 5.1
# test-step-console-quiet.ps1
# Source-level contract: "quiet-repeat" console noise reduction.
#
# Problem: every session-loop recovery re-pass (SessionLoopIter > 1) used to
# repaint the full happy-path step choreography to console ("Verifying laptop
# SSH key...ok", "Mounting files...ok", "Syncing Cursor auth...ok") even when
# the recovery silently self-healed with nothing the user needs to see. Over a
# long session with any tunnel soft-fails this produced a lot of visible
# scrollback ("too much log spam" / "scrollback flooded"). Fix: gate the routine "ok" console lines to
# the FIRST session-loop pass only; every pass keeps writing the full detail
# to the day-log file (Write-ConnectLog / connect_log) unconditionally, so no
# diagnostic signal is lost - only the repeat console repaint is suppressed.
# Failures (StepFail / step_fail) are NEVER gated - a real problem must always
# be visible on console (and still drives the existing R=retry/Q=quit prompts).
#
# ============================================================================
# EXACT NAMES IMPLEMENTERS MUST MATCH (chosen here, verbatim, do not deviate):
# ============================================================================
# WINDOWS (scripts/client/windows/connect.ps1):
#   - New script-scoped flag:            $script:StepConsoleQuiet
#     initialized to $false alongside the other step state vars
#     ($script:pendingFixes / $script:currentStepName / $script:currentStepStartedAt).
#   - Step($m): the header Write-Host (...).PadRight(46,'.') line is wrapped in
#       if (-not $script:StepConsoleQuiet) { ... }
#   - StepOk: the " ok" / " $d" Write-Host line, and the "-> fixed: $fx" loop,
#     are each wrapped in the same "if (-not $script:StepConsoleQuiet)" guard.
#     The Write-ConnectLog "STEP end: ... ok ..." call stays UNGATED (always
#     logs to the file).
#   - StepFail: UNCHANGED / ungated - always prints to console.
#   - Inside :sessionLoop, immediately after "$script:SessionLoopIter++":
#       $script:StepConsoleQuiet = ($script:SessionLoopIter -gt 1)
#
# MAC (scripts/client/mac/connect.sh):
#   - step(): returns early (before the printf header) when
#       [ "${STEP_CONSOLE_QUIET:-0}" = "1" ]
#     but still sets CURRENT_STEP_NAME / CURRENT_STEP_START and still calls
#     connect_log "STEP begin: ..." beforehand (ungated).
#   - step_ok(): still calls connect_log "STEP end: ... ok ..." unconditionally,
#     then returns early (before the printf result line) when
#       [ "${STEP_CONSOLE_QUIET:-0}" = "1" ]
#   - step_fail(): UNCHANGED / ungated - always prints to console.
#   - Right after "SESSION_LOOP_ITER=$(( SESSION_LOOP_ITER + 1 ))":
#       sets STEP_CONSOLE_QUIET=1 when SESSION_LOOP_ITER -gt 1, else 0.
#
# MUST-NOT (regression guards):
#   - StepFail / step_fail must never become conditional on the quiet flag.
#   - Write-ConnectLog / connect_log calls inside Step/StepOk (win) and
#     step()/step_ok() (mac) must remain unconditional (file logging is never
#     reduced by this change - only the console repaint).
#   - The quiet flag must not be hardcoded permanently true/false; it must be
#     derived from the session-loop iteration counter.
# ============================================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== STEP_CONSOLE_QUIET: suppress repeat session-loop step-ok console noise (source contracts) ===' -ForegroundColor Cyan
Write-Host ''

$win = Get-Content (Get-ClientFile 'windows/connect.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'mac/connect.sh') -Raw

# ----------------------------------------------------------------------------
# WINDOWS
# ----------------------------------------------------------------------------
Write-Host '--- Windows: connect.ps1 ---' -ForegroundColor Cyan

Assert ($win -match '\$script:StepConsoleQuiet\s*=\s*\$false') '$script:StepConsoleQuiet initialized to $false at script scope'

$stepFuncBlock = ''
if ($win -match '(?s)function Step\(\$m\) \{.*?\r?\n\}\r?\n') { $stepFuncBlock = $Matches[0] }
Assert ($stepFuncBlock.Length -gt 50) 'extracted Step($m) function body'
Assert (
    $stepFuncBlock -match '(?s)if\s*\(-not\s*\$script:StepConsoleQuiet\)\s*\{\s*Write-Host \("    " \+ \$m\)\.PadRight\(46,'
) 'Step() header Write-Host is gated behind "if (-not $script:StepConsoleQuiet)"'
Assert ($stepFuncBlock -match 'Write-ConnectLog "STEP begin: \$m"') 'Step() still logs "STEP begin" to the file unconditionally'

$stepOkBlock = ''
if ($win -match '(?s)function StepOk\s*\{.*?\r?\n\}\r?\n') { $stepOkBlock = $Matches[0] }
Assert ($stepOkBlock.Length -gt 50) 'extracted StepOk function body'
Assert (
    $stepOkBlock -match '(?s)if\s*\(-not\s*\$script:StepConsoleQuiet\)\s*\{' -and (
        $stepOkBlock -match 'Write-Host " \$d"' -or
        $stepOkBlock -match 'StepProgressActive'
    )
) 'StepOk result line (" ok" / " $d" / progress rewrite) is gated behind "if (-not $script:StepConsoleQuiet)"'
Assert (
    $stepOkBlock -match '(?s)if\s*\(-not\s*\$script:StepConsoleQuiet\)\s*\{\s*foreach\s*\(\$fx in \$script:pendingFixes\)'
) 'StepOk "-> fixed:" loop is gated behind "if (-not $script:StepConsoleQuiet)"'
Assert (
    $stepOkBlock -match 'Write-ConnectLog "STEP end: \$\(\$script:currentStepName\) ok ms=\$ms detail=\$detail"'
) 'StepOk still logs "STEP end...ok" to the file unconditionally'

$stepFailBlock = ''
if ($win -match '(?s)function StepFail \{.*?\r?\n\}\r?\n') { $stepFailBlock = $Matches[0] }
Assert ($stepFailBlock.Length -gt 50) 'extracted StepFail function body'
Assert ($stepFailBlock -notmatch 'StepConsoleQuiet') 'StepFail is NOT gated by $script:StepConsoleQuiet (failures always visible)'
Assert ($stepFailBlock -match 'Write-Host " failed"') 'StepFail still unconditionally prints " failed" to console'

$sessionLoopHeadOk = $win -match (
    '(?s)\$script:SessionLoopIter\+\+\s*\r?\n\s*(?:#[^\r\n]*\r?\n\s*|\$script:OrphanReclaimDoneThisEnsure\s*=\s*\$false\s*\r?\n\s*)*' +
    '\$script:StepConsoleQuiet\s*=\s*\(\$script:SessionLoopIter\s*-gt\s*1\)'
)
Assert $sessionLoopHeadOk 'sessionLoop sets $script:StepConsoleQuiet = ($script:SessionLoopIter -gt 1) right after incrementing the iter counter'

# ----------------------------------------------------------------------------
# MAC
# ----------------------------------------------------------------------------
Write-Host '--- Mac: connect.sh ---' -ForegroundColor Cyan

$macStepBlock = ''
if ($mac -match '(?s)step\(\) \{.*?\r?\n\}\r?\n') { $macStepBlock = $Matches[0] }
Assert ($macStepBlock.Length -gt 50) 'extracted step() function body'
Assert (
    $macStepBlock -match [regex]::Escape('[ "${STEP_CONSOLE_QUIET:-0}" = "1" ] && return 0')
) 'step() returns early on STEP_CONSOLE_QUIET=1 (before the printf header)'
Assert ($macStepBlock -match [regex]::Escape('connect_log "STEP begin: $*"')) 'step() still logs "STEP begin" to the file unconditionally'
Assert (
    ($macStepBlock.IndexOf('connect_log "STEP begin') -ge 0) -and
    ($macStepBlock.IndexOf('return 0') -ge 0) -and
    ($macStepBlock.IndexOf('connect_log "STEP begin') -lt $macStepBlock.IndexOf('return 0')) -and
    ($macStepBlock.IndexOf('return 0') -lt $macStepBlock.LastIndexOf("printf '%s' `"`$s`""))
) 'step() logs to file BEFORE the quiet-gate early return, and prints the header AFTER it'

$macStepOkBlock = ''
if ($mac -match '(?s)step_ok\(\)\s*\{.*?\r?\n\}\r?\n') { $macStepOkBlock = $Matches[0] }
Assert ($macStepOkBlock.Length -gt 50) 'extracted step_ok() function body'
Assert (
    $macStepOkBlock -match [regex]::Escape('[ "${STEP_CONSOLE_QUIET:-0}" = "1" ] && return 0')
) 'step_ok() returns early on STEP_CONSOLE_QUIET=1 (before the printf result line)'
Assert (
    $macStepOkBlock -match 'connect_log "STEP end: \$CURRENT_STEP_NAME ok ms=\$ms detail=\$detail"'
) 'step_ok() still logs "STEP end...ok" to the file unconditionally'
Assert (
    $macStepOkBlock.IndexOf('connect_log "STEP end') -lt $macStepOkBlock.IndexOf('return 0')
) 'step_ok() logs to file BEFORE the quiet-gate early return'

$macStepFailBlock = ''
if ($mac -match '(?s)step_fail\(\)\s*\{.*?\r?\n\}\r?\n') { $macStepFailBlock = $Matches[0] }
Assert ($macStepFailBlock.Length -gt 50) 'extracted step_fail() function body'
Assert ($macStepFailBlock -notmatch 'STEP_CONSOLE_QUIET') 'step_fail() is NOT gated by STEP_CONSOLE_QUIET (failures always visible)'
Assert ($macStepFailBlock -match [regex]::Escape("printf ' failed\n'")) 'step_fail() still unconditionally prints " failed" to console'

$macLoopHeadOk = $mac -match (
    '(?s)SESSION_LOOP_ITER=\$\(\(\s*SESSION_LOOP_ITER\s*\+\s*1\s*\)\)\s*\r?\n\s*(?:#[^\r\n]*\r?\n\s*)*' +
    'if\s*\[\s*"\$SESSION_LOOP_ITER"\s*-gt\s*1\s*\];\s*then\s*STEP_CONSOLE_QUIET=1;\s*else\s*STEP_CONSOLE_QUIET=0;\s*fi'
)
Assert $macLoopHeadOk 'Mac session loop sets STEP_CONSOLE_QUIET based on (SESSION_LOOP_ITER -gt 1) right after incrementing the iter counter'

Write-Host ''
if ($fail -gt 0) {
    Write-Host "FAILED: $fail assertion(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
