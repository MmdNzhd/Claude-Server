#Requires -Version 5.1
# test-auth-stamp-skip.ps1
# Source-level contract for writing-plans Task 2 (#6 + #7v1):
#   #6   Windows Test-CursorAuthNeedsRefresh must not flag `personal_without_profile`
#        (personalMain>=1, profileMain==0) when auth is already complete.
#        AUTH_WARN personal_cursor_dominant (>=3 threshold) still exists but is
#        gated on -not $skipAuth (skip process enum when stamp/auth skip).
#   #7v1 Windows connect.ps1 must short-circuit straight to $authNeedsRefresh=$true
#        on a real stamp MISMATCH (SyncedAt/GoldenExportedAt both non-empty and
#        different) + authComplete, WITHOUT calling the heavier
#        Test-CursorAuthNeedsRefresh (saves 2 SSH round trips). Sync must still run
#        afterward (stamp mismatch must never skip Sync).
#   Mac  git-mode.sh live cursor_auth_needs_refresh() (~3176, NOT the dead stub at
#        ~1112) gets the equivalent authComplete-aware gating for
#        personal_without_profile, fed by the caller in mac/connect.sh.
#
# ============================================================================
# EXACT NAMES IMPLEMENTERS MUST MATCH (chosen here, verbatim, do not deviate):
# ============================================================================
#
# WINDOWS (scripts/client/cursor-auth-laptop.ps1):
#   - New parameter on Test-CursorAuthNeedsRefresh:              -AuthComplete
#     (e.g. `param([string]$DbPath = '', [bool]$AuthComplete = $false)`)
#   - Gate expression (exact token sequence, whitespace-insensitive):
#       $personalMain -gt 0 -and $profileMain -eq 0 -and -not $AuthComplete
#     guarding the line that appends the 'personal_without_profile' reason.
#
# WINDOWS (scripts/client/windows/connect.ps1):
#   - Call site must pass the new param:
#       Test-CursorAuthNeedsRefresh -DbPath $gsPath -AuthComplete $authComplete
#   - New elseif branch inserted BEFORE the
#       `elseif (Get-Command Test-CursorAuthNeedsRefresh ...)` branch, using the
#     already-computed $stampCheck (SyncedAt/GoldenExportedAt both non-empty and
#     different) gated on $authComplete, which sets $authNeedsRefresh = $true and
#     logs the exact DEBUG string:
#       AUTH_DECISION stamp_mismatch_skip_needs_refresh_check
#   - AUTH_WARN personal_cursor_dominant runs only when -not $skipAuth
#     (Task 6: skip process enum on stamp-current auth skip).
#   - Sync must never be skipped on stamp mismatch: no naive
#       if ($stampCurrent -eq $false) { ... $skipAuth = $true ... }
#     pattern, and the existing `-not $authNeedsRefresh` guard on $skipAuth stays.
#
# MAC (scripts/client/git-mode.sh, live cursor_auth_needs_refresh() only, ~3176):
#   - New second positional parameter, local var name:            auth_complete
#     read as: auth_complete="${2:-0}"
#   - Gate expression guarding the personal_without_profile reason append (exact
#     token, whitespace-insensitive):
#       test_personal_cursor_dominant && [ "$auth_complete" != "1" ]
#   - golden_stale / serviceMachineId_empty / machineid_file_mismatch reasons are
#     NOT gated by auth_complete (only personal_without_profile is) - regression
#     guard.
#   - Dead stub cursor_auth_needs_refresh() at ~1112 is left untouched (single-arg,
#     no auth_complete) - not asserted here, informational only.
#
# MAC (scripts/client/mac/connect.sh, ~924-943 sync gate block):
#   - New local var, name:                                        _auth_complete
#     computed via local_cursor_auth_complete "$_cursor_gs" (mirrors the existing
#     _auth_needs_refresh=0 / cursor_auth_needs_refresh pattern already there).
#   - Call site must pass it as the second positional arg:
#       cursor_auth_needs_refresh "$_cursor_gs" "$_auth_complete"
#   - AUTH_WARN personal_cursor_dominant stays unconditional - regression guard.
# ============================================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== AUTH_STAMP_SKIP: authComplete-aware personal_without_profile + stamp-mismatch fast path (source contracts) ===' -ForegroundColor Cyan
Write-Host ''

$authLaptop = Get-Content (Get-ClientFile 'cursor-auth-laptop.ps1') -Raw
$win        = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gitMode    = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$mac        = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

# ----------------------------------------------------------------------------
# Extract focused blocks
# ----------------------------------------------------------------------------

# Windows: Test-CursorAuthNeedsRefresh function body (cursor-auth-laptop.ps1)
$authFuncBlock = ''
if ($authLaptop -match '(?s)function Test-CursorAuthNeedsRefresh \{.*?\r?\n\}\r?\n') {
    $authFuncBlock = $Matches[0]
}
Assert ($authFuncBlock.Length -gt 200) 'extracted Test-CursorAuthNeedsRefresh function body'

# Windows: connect.ps1 auth-decision block ($stampCurrent init through the
# $skipAuth gate's "AUTH_DECISION skip=" log line, so the block includes both
# the stamp-mismatch insertion point AND the -not $authNeedsRefresh skip gate).
$connectAuthBlock = ''
if ($win -match '(?s)\$stampCurrent = \$false.*?Write-ConnectLog "AUTH_DECISION skip=') {
    $connectAuthBlock = $Matches[0]
}
Assert ($connectAuthBlock.Length -gt 200) 'extracted connect.ps1 auth-decision block'

# Mac: LIVE cursor_auth_needs_refresh() body only (anchored right after
# local_cursor_auth_complete(), which immediately precedes the live definition -
# NOT the dead stub near line 1112).
$macFuncBlock = ''
if ($gitMode -match '(?s)local_cursor_auth_complete\(\) \{.*?\r?\n\}\r?\n\r?\n(?:# [^\r\n]*\r?\n)*cursor_auth_needs_refresh\(\) \{.*?\r?\n\}\r?\n') {
    $macFuncBlock = $Matches[0]
}
Assert ($macFuncBlock.Length -gt 200) 'extracted mac git-mode.sh LIVE cursor_auth_needs_refresh() body (post local_cursor_auth_complete anchor)'

# Sanity: the extracted mac block must be the live one (has golden_stale / sshx),
# not the 6-line dead stub (which has none of these).
Assert ($macFuncBlock -match 'golden_stale' -and $macFuncBlock -match 'sshx') 'extracted mac block is the LIVE definition, not the dead stub'

# Mac: connect.sh sync-gate block (~924-943)
$macGateBlock = ''
if ($mac -match '(?s)if \[ "\$EDITOR_CMD" = "cursor" \] && declare -F sync_cursor_golden_auth_status.*?if \[ "\$_skip_auth" -eq 0 \]; then') {
    $macGateBlock = $Matches[0]
}
Assert ($macGateBlock.Length -gt 200) 'extracted mac/connect.sh sync-gate block'

Write-Host '--- #6 Windows: Test-CursorAuthNeedsRefresh gains authComplete-aware gate ---' -ForegroundColor Cyan
Assert ($authFuncBlock -match '(?m)^\s*param\s*\(') 'Test-CursorAuthNeedsRefresh has a param() block'
Assert ($authFuncBlock -match '\$AuthComplete') 'Test-CursorAuthNeedsRefresh param block declares $AuthComplete'
Assert (
    $authFuncBlock -match '\$personalMain\s+-gt\s+0\s+-and\s+\$profileMain\s+-eq\s+0\s+-and\s+-not\s+\$AuthComplete'
) 'personal_without_profile reason gated by "-and -not $AuthComplete" (exact token sequence)'
Assert ($authFuncBlock -match "'personal_without_profile'") 'personal_without_profile reason string still added when the gate condition is met'

Write-Host '--- #6 Windows: AUTH_WARN personal_cursor_dominant gated on -not skipAuth ---' -ForegroundColor Cyan
Assert ($win -match "Write-ConnectLog 'AUTH_WARN personal_cursor_dominant' 'WARN'") 'connect.ps1 still logs AUTH_WARN personal_cursor_dominant'
Assert ($win -match '(?s)\$skipAuth = \$false.*?-not \$skipAuth -and \(Get-Command Test-PersonalCursorDominant') 'personal_cursor_dominant gated on -not skipAuth (skip process enum when stamp current)'
$dominantBlock = ''
if ($win -match '(?s)if \(-not \$skipAuth -and \(Get-Command Test-PersonalCursorDominant.*?AUTH_WARN personal_cursor_dominant[^\r\n]*\r?\n\s*\}\r?\n\s*\}') {
    $dominantBlock = $Matches[0]
}
Assert ($dominantBlock.Length -gt 20) 'extracted Test-PersonalCursorDominant warn block'
Assert ($dominantBlock -notmatch 'authComplete|AuthComplete') 'dominant-warn block not coupled to authComplete (dominant threshold check stays independent)'

Write-Host '--- Task 2 hardening: Windows golden_stale reason unaffected by AuthComplete (mutation-testing regression guard) ---' -ForegroundColor Cyan
$goldenStaleWinSeg = ''
if ($authFuncBlock -match '(?s)if \(\$goldenExportedAt -and \(\$syncedAt -ne \$goldenExportedAt\)\) \{.*?\}') {
    $goldenStaleWinSeg = $Matches[0]
}
Assert ($goldenStaleWinSeg.Length -gt 10) 'extracted Windows golden_stale condition block'
Assert ($goldenStaleWinSeg -notmatch 'AuthComplete') 'Windows golden_stale is NOT gated by AuthComplete (regression guard)'

Write-Host '--- #7v1 Windows: stamp-mismatch fast path sets authNeedsRefresh without calling Test-CursorAuthNeedsRefresh ---' -ForegroundColor Cyan
Assert ($connectAuthBlock -match 'stamp_mismatch_skip_needs_refresh_check') 'connect.ps1 has the stamp_mismatch_skip_needs_refresh_check log string'
Assert ($connectAuthBlock -match '\$authComplete') 'stamp-mismatch branch condition references $authComplete'
Assert (
    $connectAuthBlock -match 'stampCheck\.SyncedAt' -and $connectAuthBlock -match 'stampCheck\.GoldenExportedAt'
) 'stamp-mismatch branch condition inspects $stampCheck.SyncedAt / $stampCheck.GoldenExportedAt'

$idxMismatch  = $connectAuthBlock.IndexOf('stamp_mismatch_skip_needs_refresh_check')
$idxNeedsCall = $connectAuthBlock.IndexOf('Test-CursorAuthNeedsRefresh -DbPath')
Assert ($idxMismatch -ge 0) 'stamp_mismatch_skip_needs_refresh_check present in auth-decision block'
Assert ($idxNeedsCall -ge 0) 'Test-CursorAuthNeedsRefresh -DbPath call present in auth-decision block'
Assert (
    ($idxMismatch -ge 0) -and ($idxNeedsCall -ge 0) -and ($idxMismatch -lt $idxNeedsCall)
) 'stamp-mismatch branch appears BEFORE the elseif that calls Test-CursorAuthNeedsRefresh'

Assert (
    $connectAuthBlock -match '(?s)(\$authNeedsRefresh\s*=\s*\$true[\s\S]{0,250}stamp_mismatch_skip_needs_refresh_check|stamp_mismatch_skip_needs_refresh_check[\s\S]{0,250}\$authNeedsRefresh\s*=\s*\$true)'
) 'stamp-mismatch branch sets $authNeedsRefresh = $true'

Write-Host '--- #7v1 Windows: new call site passes -AuthComplete to Test-CursorAuthNeedsRefresh ---' -ForegroundColor Cyan
Assert (
    $connectAuthBlock -match 'Test-CursorAuthNeedsRefresh\s+-DbPath\s+\$gsPath\s+-AuthComplete\s+\$authComplete'
) 'connect.ps1 calls Test-CursorAuthNeedsRefresh -DbPath $gsPath -AuthComplete $authComplete'

Write-Host '--- #7v1 / item 3 Windows: Sync must never be skipped on stamp mismatch (regression guard) ---' -ForegroundColor Cyan
Assert (
    $win -notmatch '(?s)if\s*\(\s*\$stampCurrent\s*-eq\s*\$false\s*\)\s*\{[\s\S]{0,150}\$skipAuth\s*=\s*\$true'
) 'no naive "$stampCurrent -eq $false -> skipAuth=$true" bug pattern'
Assert (
    $connectAuthBlock -match '-not\s+\$authNeedsRefresh\)\s*\{'
) '$skipAuth gate still requires -not $authNeedsRefresh (mismatch -> authNeedsRefresh=$true -> sync still runs)'

Write-Host '--- #6 Mac: live cursor_auth_needs_refresh() gains authComplete-aware gate ---' -ForegroundColor Cyan
Assert ($macFuncBlock -match 'auth_complete\s*=\s*"\$\{2:-0\}"') 'live cursor_auth_needs_refresh() reads 2nd positional arg into local auth_complete ("${2:-0}")'
Assert (
    $macFuncBlock -match '\[\s*\$personal_main\s+-gt\s+0\s*\]\s*&&\s*\[\s*\$profile_main\s+-eq\s+0\s*\]\s*&&\s*\[\s*"\$auth_complete"\s*!=\s*"1"\s*\]'
) 'personal_without_profile reason gated by "[ $personal_main -gt 0 ] && [ $profile_main -eq 0 ] && [ "$auth_complete" != "1" ]" (raw threshold, parity with Windows -gt 0)'
Assert ($macFuncBlock -match 'personal_without_profile') 'personal_without_profile reason string still added when the gate condition is met'

Write-Host '--- #6 Mac: other reasons unaffected by auth_complete (regression guard) ---' -ForegroundColor Cyan
$goldenStaleSeg = ''
if ($macFuncBlock -match '(?s)if \[ -n "\$golden_exported" \].*?reasons="\$\{reasons\}golden_stale "') {
    $goldenStaleSeg = $Matches[0]
}
Assert ($goldenStaleSeg.Length -gt 20) 'extracted golden_stale reason segment'
Assert ($goldenStaleSeg -notmatch 'auth_complete') 'golden_stale reason is NOT gated by auth_complete'
$midSeg = ''
if ($macFuncBlock -match "(?s)machineid_file_mismatch.*?\r?\n\s*fi") {
    $midSeg = $Matches[0]
}
Assert ($midSeg -notmatch 'auth_complete') 'machineid_file_mismatch reason is NOT gated by auth_complete'

Write-Host '--- Task 2 hardening: Mac personal_without_profile threshold parity with Windows (currently a real bug, awaiting parallel fix) ---' -ForegroundColor Cyan
Assert ($macFuncBlock -notmatch 'test_personal_cursor_dominant') 'Mac cursor_auth_needs_refresh() no longer delegates personal_without_profile to the >=3 dominant-only helper (uses its own >0 threshold instead)'
Assert ($macFuncBlock -match 'personal_main\s*-gt\s*0') 'Mac cursor_auth_needs_refresh() gates personal_without_profile by personal_main -gt 0 (matches Windows threshold)'
Assert ($mac -match 'test_personal_cursor_dominant') 'mac/connect.sh still uses test_personal_cursor_dominant for the AUTH_WARN personal_cursor_dominant path (unchanged, >=3 threshold preserved)'

Write-Host '--- #6 Mac: mac/connect.sh caller computes and passes _auth_complete ---' -ForegroundColor Cyan
# NOTE: regexes below use a negative lookbehind for a preceding letter so they
# do NOT accidentally match the unrelated "...cursor_auth_complete" substring
# that already exists inside the pre-existing function name local_cursor_auth_complete.
Assert (
    $macGateBlock -match '(?<![a-zA-Z])_auth_complete\s*=\s*0'
) 'mac/connect.sh sync-gate block initializes _auth_complete=0 (mirrors existing _auth_needs_refresh=0 pattern)'
Assert (
    $macGateBlock -match '(?s)local_cursor_auth_complete\s+"\$_cursor_gs"[\s\S]{0,40}(?<![a-zA-Z])_auth_complete\s*=\s*1'
) 'mac/connect.sh sets _auth_complete=1 from local_cursor_auth_complete "$_cursor_gs" result'
Assert (
    $macGateBlock -match 'cursor_auth_needs_refresh\s+"\$_cursor_gs"\s+"\$_auth_complete"'
) 'mac/connect.sh calls cursor_auth_needs_refresh "$_cursor_gs" "$_auth_complete" (both args)'

Write-Host '--- #6 Mac: AUTH_WARN personal_cursor_dominant unaffected (regression guard) ---' -ForegroundColor Cyan
Assert (
    $macGateBlock -match "connect_log 'AUTH_WARN personal_cursor_dominant' 'WARN'"
) 'mac/connect.sh still logs AUTH_WARN personal_cursor_dominant unconditionally'

Write-Host ''
if ($fail -gt 0) {
    Write-Host "FAILED: $fail assertion(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
