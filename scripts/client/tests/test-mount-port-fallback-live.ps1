# test-mount-port-fallback-live.ps1 - Bug 1 LIVE (RED phase, Wave 1 slice 1A/1B).
#
# Proves two real, currently-shipping bugs in the tunnel-port formula chain:
#
#   1a. scripts/server/claude-mount.sh, function _load_global (~lines 39-41):
#         if [ -z "$TUNNEL_PORT" ]; then
#             TUNNEL_PORT=$((20000 + $(id -u)))
#         fi
#       This is the deprecated `20000 + UID` formula. The correct, currently-canonical
#       formula (see research citations below) is `20000 + (UID-1000)*10 + slot`.
#
#   1b. scripts/client/git-mode.ps1, function Push-ServerConnectConf, embedded bash
#       here-string $remoteBody (~lines 2821-2862), AM_ONLY branch:
#         if [ "$AM_ONLY" = "1" ]; then
#           PORT_OUT=$CUR_PORT
#           ...
#       When $CUR_PORT (read from a prior ~/.claude-connect.conf, or blank when no such
#       line/file exists) is empty, PORT_OUT stays blank and gets written as
#       `TUNNEL_PORT=` into the conf file - which is exactly the blank input that then
#       triggers claude-mount.sh's bad fallback in 1a.
#
# Research (read for real, cited here so this test's expectations are traceable):
#   - scripts/client/git-mode.ps1 Get-TunnelPortUserBase (~line 1054-1074):
#       $offset = $uid - 1000; if ($offset -lt 0) { $offset = 0 }
#       return 20000 + ($offset * 10)                      # <- base only, slot added by caller
#   - scripts/client/git-mode.sh tunnel_port_user_base (~line 2031-2039):
#       offset=$(( uid_str - 1000 )); [ "$offset" -lt 0 ] && offset=0
#       echo $(( base + offset * 10 ))                      # base = ${CONNECT_PORT_BASE:-20000}
#   Both canonical implementations agree: full port = 20000 + (UID-1000)*10 + slot (slot
#   added on top of the base by their respective callers, e.g. acquire_tunnel_port).
#
# Test 1 (bash side): dot-extracts the REAL _load_global function body verbatim out of
# the real claude-mount.sh file via brace-range `sed` (the bash analogue of this repo's
# usual Get-FunctionSource brace-extraction idiom for PowerShell), runs it for real under
# WSL bash against a real temp $HOME/.claude-connect.conf with TUNNEL_PORT blank (and,
# separately, the conf file entirely absent), and compares the REAL resulting
# $TUNNEL_PORT against both formulas computed from the REAL `id -u` in that same bash
# invocation.
#
# Test 2 (PowerShell side): extracts the REAL $remoteBody here-string template text
# verbatim out of git-mode.ps1 via regex, sets the same PowerShell variables
# Push-ServerConnectConf sets before building it, and uses PowerShell's own
# $ExecutionContext.InvokeCommand.ExpandString() - the same interpolation engine that
# powers `@" ... "@` here-strings - to produce the REAL bash text that would be shipped
# to the server. That real, fully-expanded bash text is then executed for real via WSL
# bash (not hand-simulated) against a temp $HOME with no prior conf file, proving the
# AM_ONLY branch really does publish a blank TUNNEL_PORT.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function ConvertTo-WslPath([string]$WinPath) {
    $full = [System.IO.Path]::GetFullPath($WinPath)
    if ($full -match '^([A-Za-z]):(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = ($Matches[2] -replace '\\', '/')
        return "/mnt/$drive$rest"
    }
    throw "Cannot convert path to WSL form: $WinPath"
}

Write-Host ''
Write-Host '=== Tunnel port fallback formula - Bug 1a/1b (LIVE) ===' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Preflight: confirm WSL bash is actually reachable before relying on it.
# ---------------------------------------------------------------------------
$bashOk = $false
try {
    $probe = & bash -c "echo BASH_OK" 2>$null
    if ($LASTEXITCODE -eq 0 -and ($probe -join "`n") -match 'BASH_OK') { $bashOk = $true }
} catch { $bashOk = $false }

$tempFiles = @()

if (-not $bashOk) {
    Write-Host '  LIMITATION  WSL bash not reachable from this shell - Test 1 (claude-mount.sh _load_global) cannot execute. Documenting this explicitly rather than silently skipping. Falling back to source-text citation only for 1a (insufficient alone per the no-pattern-matching-only rule) - marking as FAIL so this is visible, not silently green.' -ForegroundColor Yellow
    $fail++
} else {
    # -----------------------------------------------------------------------
    # Test 1 (bash side): real WSL bash execution of the real _load_global body.
    # -----------------------------------------------------------------------
    Write-Host ''
    Write-Host '--- Test 1: claude-mount.sh _load_global (bash, real execution) ---' -ForegroundColor Cyan

    $mountShWin = Get-ServerFile 'server/claude-mount.sh'
    if (-not (Test-Path $mountShWin)) {
        Write-Host "  FAIL  claude-mount.sh not found at $mountShWin - live test cannot run (source drifted)" -ForegroundColor Red
        $fail++
    } else {
        $mountShWsl = ConvertTo-WslPath $mountShWin

        $bashScript = @'
set -u
SCRIPT="__SCRIPT_PATH__"
REAL_UID=$(id -u)
SLOT=5
DEPRECATED=$((20000 + REAL_UID))
OFFSET=$((REAL_UID - 1000))
if [ "$OFFSET" -lt 0 ]; then OFFSET=0; fi
CORRECT=$((20000 + OFFSET * 10 + SLOT))

TMPHOME=$(mktemp -d)
export HOME="$TMPHOME"
# Mirrors claude-mount.sh's own file-scope definition (claude-mount.sh line 5):
#   CONNECT_CONF="$HOME/.claude-connect.conf"
CONNECT_CONF="$HOME/.claude-connect.conf"
TUNNEL_PORT=""
GIT_MODE="off"
LAPTOP_OS="windows"
ACTIVE_MOUNT=""

FUNC_SRC="$(sed -n '/^_load_global()/,/^}/p' "$SCRIPT")"
if [ -z "$FUNC_SRC" ]; then
    echo "EXTRACT_FAILED"
    rm -rf "$TMPHOME"
    exit 1
fi
eval "$FUNC_SRC"

echo "REAL_UID=$REAL_UID"
echo "DEPRECATED_FORMULA=$DEPRECATED"
echo "CORRECT_FORMULA_SLOT${SLOT}=$CORRECT"

# Case A: conf file present, TUNNEL_PORT= line present but blank (exactly what
# Push-ServerConnectConf's AM_ONLY branch writes per bug 1b).
printf 'TUNNEL_PORT=\nLAPTOP_USER=testuser\n' > "$CONNECT_CONF"
TUNNEL_PORT=""
_load_global
echo "CASE_BLANK_LINE_TUNNEL_PORT=$TUNNEL_PORT"

# Case B: conf file entirely absent (no ~/.claude-connect.conf at all).
rm -f "$CONNECT_CONF"
TUNNEL_PORT=""
_load_global
echo "CASE_NO_FILE_TUNNEL_PORT=$TUNNEL_PORT"

rm -rf "$TMPHOME"
'@
        $bashScript = $bashScript.Replace('__SCRIPT_PATH__', $mountShWsl)
        $bashScript = ($bashScript -replace "`r`n", "`n") -replace "`r", "`n"

        $tmpSh = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_test1_load_global_$([guid]::NewGuid().ToString('N')).sh")
        $tempFiles += $tmpSh
        [System.IO.File]::WriteAllText($tmpSh, $bashScript)
        $tmpShWsl = ConvertTo-WslPath $tmpSh

        $out = & bash "$tmpShWsl" 2>&1
        $outText = ($out -join "`n")
        Write-Host '  --- real bash output ---' -ForegroundColor DarkGray
        $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

        function Get-KV([string]$Text, [string]$Key) {
            $m = [regex]::Match($Text, "(?m)^$Key=(.*)$")
            if ($m.Success) { return $m.Groups[1].Value.Trim() }
            return $null
        }

        $realUid       = Get-KV $outText 'REAL_UID'
        $deprecated    = Get-KV $outText 'DEPRECATED_FORMULA'
        $correctSlot5  = Get-KV $outText 'CORRECT_FORMULA_SLOT5'
        $caseBlank     = Get-KV $outText 'CASE_BLANK_LINE_TUNNEL_PORT'
        $caseNoFile    = Get-KV $outText 'CASE_NO_FILE_TUNNEL_PORT'

        Assert ($outText -notmatch 'EXTRACT_FAILED') 'real _load_global function body was extracted from claude-mount.sh (source not drifted)'
        Assert ($null -ne $realUid -and $null -ne $deprecated -and $null -ne $correctSlot5) 'real bash computed both formulas from the real id -u'

        Write-Host "  INFO  real uid=$realUid deprecated_formula(20000+uid)=$deprecated correct_formula(20000+(uid-1000)*10+slot5)=$correctSlot5" -ForegroundColor Gray

        if ($deprecated -eq $correctSlot5) {
            Write-Host '  LIMITATION  for this real uid, slot 5 happens to make both formulas coincide - not expected, but noting explicitly per instructions rather than asserting a false positive.' -ForegroundColor Yellow
        }

        # ---------------------------------------------------------------------
        # BUG 1a FIX VERIFICATION (Worker G, 2026-07-24). Originally this block
        # asserted the bug's PRESENCE (caseBlank/caseNoFile equal the deprecated
        # 20000+uid formula) as a RED characterization before the fix landed. Now
        # that claude-mount.sh's _load_global fallback has been fixed, these
        # asserts check the FIX directly instead: the fallback must equal the
        # correct formula with slot defaulted to 0 (claude-mount.sh cannot know
        # the real slot - only the client can), must NOT regress back to the
        # deprecated 20000+uid value, and must emit a loud stderr warning rather
        # than silently guessing.
        # ---------------------------------------------------------------------
        $offsetPs = [int]$realUid - 1000
        if ($offsetPs -lt 0) { $offsetPs = 0 }
        $correctSlot0 = 20000 + ($offsetPs * 10)
        Write-Host "  INFO  correct_formula_slot0(20000+(uid-1000)*10+0)=$correctSlot0 (claude-mount.sh's own fallback default slot)" -ForegroundColor Gray
        Assert ($caseBlank -eq $correctSlot0) "BUG 1a FIXED: real _load_global (blank TUNNEL_PORT= line) sets TUNNEL_PORT=$caseBlank which equals the correct slot-0 fallback formula ($correctSlot0), not the deprecated formula ($deprecated)"
        Assert ($caseBlank -ne $deprecated -or $deprecated -eq $correctSlot0) "real TUNNEL_PORT=$caseBlank does NOT regress to the deprecated 20000+uid formula ($deprecated)"
        Assert ($caseNoFile -eq $correctSlot0) "BUG 1a FIXED (conf file entirely absent): real _load_global sets TUNNEL_PORT=$caseNoFile which equals the correct slot-0 fallback formula ($correctSlot0)"
        Assert ($outText -match 'warn:.*TUNNEL_PORT missing') 'BUG 1a FIXED (loud-not-silent): real _load_global fallback prints a stderr warning instead of silently guessing a wrong port'
    }
}

# ---------------------------------------------------------------------------
# Test 2 (PowerShell side): real extraction + real PowerShell interpolation +
# real WSL bash execution of Push-ServerConnectConf's AM_ONLY remote body.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- Test 2: Push-ServerConnectConf AM_ONLY remote body (bash, real execution) ---' -ForegroundColor Cyan

$gitModeWin = Get-ClientFile 'git-mode.ps1'
$gmContent = Get-Content $gitModeWin -Raw

# Real Get-FunctionSource brace extraction, per the established idiom (confirms
# Push-ServerConnectConf itself still exists / hasn't drifted structurally).
$funcSrc = Get-FunctionSource -Content $gmContent -Name 'Push-ServerConnectConf'
if (-not $funcSrc) {
    Write-Host '  FAIL  could not extract Push-ServerConnectConf - live test cannot run (source drifted)' -ForegroundColor Red
    $fail++
} else {
    Assert ($funcSrc -match [regex]::Escape('PORT_OUT=`$CUR_PORT')) 'real Push-ServerConnectConf source (brace-extracted) still contains the AM_ONLY `PORT_OUT=$CUR_PORT` line under test'

    # Extract the REAL $remoteBody here-string template text verbatim (regex over the
    # whole file, not the brace-extracted function text, since Get-FunctionSource does
    # not need to be re-purposed for here-strings - this is a separate, explicit
    # extraction of the exact template PowerShell interpolates at runtime).
    $m = [regex]::Match($gmContent, '(?s)\$remoteBody = @"\r?\n(.*?)\r?\n"@')
    if (-not $m.Success) {
        Write-Host '  FAIL  could not regex-extract $remoteBody here-string template from git-mode.ps1 - live test cannot run (source drifted)' -ForegroundColor Red
        $fail++
    } else {
        $templateText = $m.Groups[1].Value

        # Set the exact same PowerShell variables Push-ServerConnectConf sets right
        # before building $remoteBody (see git-mode.ps1 ~lines 2810-2817), to
        # controlled test values. AM_ONLY=1 reproduces the non-primary-publisher
        # scenario from bug 1b; PORT is the session's OWN real tunnel port (what
        # SHOULD end up published when there is no prior CUR_PORT to preserve).
        $clearFlag   = '0'
        $preferEsc   = ''
        $lu          = 'testuser'
        $portEsc     = '20025'
        $slotEsc     = '0'
        $modeEsc     = 'off'
        $hkEsc       = ''
        $amOnlyFlag  = '1'

        # REAL PowerShell interpolation - the exact same engine `@" ... "@` here-strings
        # use - applied to the REAL extracted template text. Not a hand-simulation.
        $expanded = $ExecutionContext.InvokeCommand.ExpandString($templateText)
        # Same CRLF normalization Push-ServerConnectConf itself applies before shipping.
        $expanded = ($expanded -replace "`r`n", "`n") -replace "`r", "`n"

        Write-Host '  --- real expanded bash text (post PowerShell interpolation) ---' -ForegroundColor DarkGray
        $expanded -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

        $wrapper = @"
set -u
TMPHOME=`$(mktemp -d)
export HOME="`$TMPHOME"
$expanded
echo "---CONF_CONTENTS---"
cat "`$HOME/.claude-connect.conf"
rm -rf "`$TMPHOME"
"@
        $wrapper = ($wrapper -replace "`r`n", "`n") -replace "`r", "`n"

        $tmpSh2 = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_test2_am_only_$([guid]::NewGuid().ToString('N')).sh")
        $tempFiles += $tmpSh2
        [System.IO.File]::WriteAllText($tmpSh2, $wrapper)

        if (-not $bashOk) {
            Write-Host '  LIMITATION  WSL bash not reachable - cannot execute the real extracted+expanded bash text for Test 2 either. Source-text-only would not satisfy the no-pattern-matching-only rule, so this half is marked FAIL rather than silently skipped.' -ForegroundColor Yellow
            $fail++
        } else {
            $tmpSh2Wsl = ConvertTo-WslPath $tmpSh2
            $out2 = & bash "$tmpSh2Wsl" 2>&1
            $out2Text = ($out2 -join "`n")
            Write-Host '  --- real bash output ---' -ForegroundColor DarkGray
            $out2 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

            $pushResultLine = ($out2 | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
            $tunnelPortLine = [regex]::Match($out2Text, '(?m)^TUNNEL_PORT=(.*)$')
            $writtenPort = if ($tunnelPortLine.Success) { $tunnelPortLine.Groups[1].Value.Trim() } else { $null }

            Assert ($null -ne $pushResultLine) 'real bash execution produced a PUSH_CONF_RESULT line (script ran to completion)'
            Assert ($pushResultLine -match 'am_only=1') "real PUSH_CONF_RESULT confirms AM_ONLY=1 branch actually ran: $pushResultLine"
            Assert ($pushResultLine -match 'publish_port=0') "real PUSH_CONF_RESULT confirms PUBLISH_PORT=0 in the AM_ONLY branch (session's real port $portEsc is discarded): $pushResultLine"

            # -----------------------------------------------------------------
            # BUG 1b FIX VERIFICATION (Worker G, 2026-07-24). Originally this assert
            # checked that TUNNEL_PORT= was written BLANK (RED characterization of
            # the bug before the fix landed). Now that the AM_ONLY branch falls back
            # to the session's own $PORT when $CUR_PORT is empty, the written conf
            # must contain that real port, not a blank line - this is exactly the
            # blank that used to feed claude-mount.sh's bad 20000+uid fallback (1a).
            # -----------------------------------------------------------------
            Assert ($writtenPort -eq $portEsc) "BUG 1b FIXED: real conf file written by the real extracted+executed AM_ONLY branch has TUNNEL_PORT=$writtenPort (the session's real port $portEsc), not blank, even though CUR_PORT was empty (no prior conf)"
        }
    }
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
foreach ($f in $tempFiles) {
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (bugs 1a and 1b fixes verified live - GREEN)' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
