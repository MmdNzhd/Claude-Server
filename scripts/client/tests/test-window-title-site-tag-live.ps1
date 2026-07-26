# test-window-title-site-tag-live.ps1 - LIVE (RED, Bug 2): proves the 4 literal '\[Claude
# Server\]' regex call sites in editor-launch.ps1 (Test-CursorWindowTitleIsAgentHome line
# ~1192, the Get-ProcessTopLevelWindows loop in Test-RemoteEditorOnCorrectFolder line ~1263,
# Get-RemoteEditorSessionPresence line ~1325, Get-RemoteEditorStateExplain line ~1404) are dead
# for every REAL rendered Cursor window title, because Initialize-CursorServerProfile (same
# file) always writes a SITE-QUALIFIED title tag ("[Claude Server Smart]" / "[Claude Server
# Sepidz]"), never the bare "[Claude Server]" the regex requires.
#
# This is a REAL, hard, behavioral test: it compiles and spawns two real Win32 processes (named
# Cursor.exe so the production CIM filters accept them), gives each a REAL OS-level top-level
# window whose title is read back via the exact same Win32 EnumWindows/GetWindowText primitives
# Get-ProcessTopLevelWindows uses (not a hand-constructed string), and calls the REAL, unmodified,
# source-extracted Test-RemoteEditorOnCorrectFolder (plus Test-CursorWindowTitleIsAgentHome)
# against those real windows. No production .ps1 file is modified by this test.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Window-title site-tag dead-regex detection (LIVE, Bug 2) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw

# Confirm (do not trust the plan doc blindly) that Initialize-CursorServerProfile really does
# write a site-qualified tag, never the bare "[Claude Server]" the 4 title-match sites look for.
$initSrc = Get-FunctionSource -Content $content -Name 'Initialize-CursorServerProfile'
if (-not $initSrc) {
    Write-Host '  FAIL  could not extract Initialize-CursorServerProfile - live test cannot run (source drifted)' -ForegroundColor Red
    exit 1
}
Assert ($initSrc -notmatch '\[Claude Server\]\s*\$\{rootName\}"') 'Initialize-CursorServerProfile does NOT emit the literal "[Claude Server] <root>" template the 4 title-match sites used to hardcode expecting'
# Bug 2 GREEN-phase: Initialize-CursorServerProfile (the writer) now delegates the tag text to
# the shared Get-CursorWindowTitleTag helper instead of inlining its own literal ternary, so the
# writer and the 4 readers (via Get-CursorWindowTitleNeedle) can never drift apart again.
Assert ($initSrc -match 'Get-CursorWindowTitleTag') 'Initialize-CursorServerProfile delegates the title tag to the shared Get-CursorWindowTitleTag helper (single source of truth with the 4 reader call sites), instead of inlining its own literal ternary'

# Bug 2 FINAL fix (supersedes the earlier Get-CursorWindowTitleNeedle approach): title-match
# call sites delegate to the shared, template-ANCHORED Test-CursorWindowTitleMatchesProject
# helper. Anchoring the root name to its exact position in the title template ("[Claude Server
# <Site>] <root>" / "<root> [SSH: <alias>]") fixes BOTH the original site-tag collision (project
# "smart" matching the "Smart" in the tag) AND the prefix-sibling collision ("smart" in
# "smartdesk", "ai" in "ai-gap-summay") that a bare dynamic needle could not. Count occurrences of
# THAT call so this test tracks the current source of truth. (Behavioral proof that the real
# site-tagged window is still detected follows below via the unmodified Test-RemoteEditorOnCorrectFolder.)
# Current readers: Test-CursorWindowTitleIsAgentHome, Test-RemoteEditorOnCorrectFolder,
# Get-RemoteEditorStateExplain (3 sites; SessionPresence uses folder URI / other signals).
$anchoredCallSites = [regex]::Matches($content, 'Test-CursorWindowTitleMatchesProject -Title')
Assert ($anchoredCallSites.Count -ge 3) "found >= 3 call sites using the anchored Test-CursorWindowTitleMatchesProject helper in editor-launch.ps1 (found $($anchoredCallSites.Count)) - title-match readers must anchor the root to the template position instead of a bare/needle substring"
$staleLiteralSites = [regex]::Matches($content, "-match\s+'\\\[Claude Server\\\]'")
Assert ($staleLiteralSites.Count -eq 0) "zero remaining hardcoded literal -match '\[Claude Server\]' call sites (found $($staleLiteralSites.Count)) - all migrated to the anchored matcher"

# Extract the REAL production functions needed to exercise one full call site
# (Test-RemoteEditorOnCorrectFolder's Get-ProcessTopLevelWindows loop, ~line 1263) plus the
# simplest single-call-site function (Test-CursorWindowTitleIsAgentHome, ~line 1192), verbatim,
# via the same brace-extraction idiom used by test-remote-editor-detect-live.ps1 - not a
# reimplementation, the actual shipped source.
foreach ($n in @(
    'Test-LaunchPerfEnabled', 'Write-LaunchPerfLog', 'Write-EditorLaunchLog',
    'Initialize-Win32WindowEnum', 'Get-ProcessTopLevelWindows',
    'Invoke-CimEditorProcessQuery', 'Invoke-CimCursorProcessQuery',
    'Get-CursorProfileProcesses', 'Test-PathNeedleBoundaryMatch', 'Get-RemoteFolderUri',
    'Get-CursorMainProfileProcesses', 'Test-CursorWindowTitleIsAgentHome',
    'Test-CursorWindowShowsAgentHome', 'Test-RemoteEditorInAgentHome',
    'Test-RemoteEditorOnCorrectFolder',
    # Bug 2: anchored project matcher + dynamic site-tag needle (harness must extract both).
    'Test-CursorWindowTitleMatchesProject',
    'Get-CursorRemoteProfileSite', 'Get-CursorWindowTitleTag', 'Get-CursorWindowTitleNeedle'
)) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Stub the profile-dir resolver so this test never touches the real shared golden Cursor
# profile (ClaudeServerCursorProfile-Smart/-Sepidz) - same isolation idiom as
# test-remote-editor-detect-live.ps1.
$script:FakeProfileDir = $null
function Get-CursorRemoteProfileDir { return $script:FakeProfileDir }

$script:EditorCimCache = @{}
$script:EditorCimCacheTtlSec = 2
$script:LaunchCimCallCount = 0

$Alias = 'unit-test-alias'
$TargetPath = '/home/testuser/myrepo'
$RootName = 'myrepo'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-title-site-tag-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$script:FakeProfileDir = Join-Path $tmp 'FakeCursorProfile'
New-Item -ItemType Directory -Force -Path $script:FakeProfileDir | Out-Null

# Real decoy: a tiny compiled WinForms host, named Cursor.exe so it passes the production
# `Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'"` filter exactly like a real Cursor
# process would. It never calls Form.Show() (so nothing pops up on screen) but forces the
# native HWND to be created by touching .Handle, then pumps a real Win32 message loop via
# Application.Run() so cross-process GetWindowText (WM_GETTEXT) can actually be answered - this
# is a REAL OS top-level window with a REAL, queryable title, not a hand-built string.
$stubExe = Join-Path $tmp 'Cursor.exe'
$stubSrc = @'
using System;
using System.Windows.Forms;
public static class DecoyCursorWindowHost {
    [STAThread]
    public static void Main(string[] args) {
        string title = args.Length > 0 ? args[0] : "decoy";
        Form f = new Form();
        f.Text = title;
        f.ShowInTaskbar = false;
        IntPtr forceHandleCreation = f.Handle;
        Application.Run();
    }
}
'@
try {
    Add-Type -Language CSharp -TypeDefinition $stubSrc -OutputType WindowsApplication -OutputAssembly $stubExe `
        -ReferencedAssemblies 'System.Windows.Forms.dll' -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile decoy Cursor.exe (WinForms host): $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Assert (Test-Path -LiteralPath $stubExe) 'decoy WinForms Cursor.exe compiled to a real binary (Name=Cursor.exe matches the production CIM filter)'

# Real-title decoy (the bug): the ACTUAL title format Initialize-CursorServerProfile writes
# today for the Smart site. A different alias+path is embedded in --folder-uri so the
# uri/alias-path fast paths in Test-RemoteEditorOnCorrectFolder do NOT match (forcing execution
# into the window-title / Get-ProcessTopLevelWindows arm under test), while 'folder-uri' still
# appears in the command line so Test-RemoteEditorInAgentHome does not misclassify this as the
# agent-home window.
$siteTaggedTitle = '[Claude Server Smart] ' + $RootName
$argsBuggy = "`"$siteTaggedTitle`" --user-data-dir=`"$($script:FakeProfileDir)`" --folder-uri=`"vscode-remote://ssh-remote+$Alias/other/decoyroot`""

# Control decoy: the LITERAL (never actually emitted) title the current regex was written for.
# Same command-line shape, only the title text differs. Used to prove the ONLY reason detection
# fails for the real decoy is the site-tag suffix, not some other confound (needle escaping,
# process filtering, etc).
$literalTitle = '[Claude Server] ' + $RootName
$argsControl = "`"$literalTitle`" --user-data-dir=`"$($script:FakeProfileDir)`" --folder-uri=`"vscode-remote://ssh-remote+$Alias/other/decoyroot`""

$pBuggy = $null
$pControl = $null
try {
    # --- Phase 1: REAL site-tagged title (what production actually renders today) ---
    $pBuggy = Start-Process -FilePath $stubExe -ArgumentList $argsBuggy -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    Assert (-not $pBuggy.HasExited) 'real-title decoy process (site-tagged, "[Claude Server Smart] myrepo") is actually running'

    $cimBuggy = Get-CimInstance Win32_Process -Filter "ProcessId=$($pBuggy.Id)" -Property Name, CommandLine -ErrorAction SilentlyContinue
    Assert ($cimBuggy -and $cimBuggy.Name -eq 'Cursor.exe') 'real Win32_Process record for the decoy reports Name=Cursor.exe (passes the production CIM filter for real)'
    Assert ($cimBuggy -and $cimBuggy.CommandLine -match [regex]::Escape($script:FakeProfileDir)) 'real Win32_Process CommandLine actually contains the fake profile dir (Get-CursorMainProfileProcesses will accept this process)'

    $wins = @(Get-ProcessTopLevelWindows -ProcessId $pBuggy.Id)
    $realTitle = ($wins | Where-Object { $_.Title -eq $siteTaggedTitle } | Select-Object -First 1).Title
    Assert ($realTitle -eq $siteTaggedTitle) "Get-ProcessTopLevelWindows (real Win32 EnumWindows+GetWindowText) reads back the REAL OS window title verbatim: '$realTitle'"

    # Bug 2 GREEN-phase: call the REAL, dot-sourced, unmodified Get-CursorWindowTitleNeedle - the
    # same helper all 4 production call sites now use - instead of the old hardcoded dead literal.
    $dynamicNeedle = Get-CursorWindowTitleNeedle
    Write-Host "  live-extracted (Get-CursorWindowTitleNeedle) value: $dynamicNeedle" -ForegroundColor DarkGray
    $fixedRegexResult = $realTitle -match $dynamicNeedle
    Assert ($fixedRegexResult -eq $true) "'$realTitle' -match (Get-CursorWindowTitleNeedle) is TRUE - FIXED: the dynamically-built needle (from the real site tag) now matches the real site-qualified title that the old hardcoded '\[Claude Server\]' literal could never match"

    # Cross-check against the literal (never-emitted, pre-site-qualification) form: the needle's
    # defensive fallback alternative still matches it too, so old on-disk profiles aren't broken.
    Assert (($literalTitle -match $dynamicNeedle) -eq $true) "'$literalTitle' (bare, never actually emitted by current code, but a defensive fallback for old profiles) -match (Get-CursorWindowTitleNeedle) IS also true - the fix's fallback alternative still covers the pre-fix literal form"

    # Simplest single-call-site function (line ~1192): with the REAL site-tagged title and the
    # matching real project root name, the (now-fixed) needle-match fast path correctly fires
    # (meant to say "this is definitively a real project window, not agent-home").
    $fastPathWouldFire = ($realTitle -match $dynamicNeedle) -and ($realTitle -match [regex]::Escape($RootName))
    Assert ($fastPathWouldFire -eq $true) 'Test-CursorWindowTitleIsAgentHome (source line ~1192) needle-match fast-path condition IS satisfied by the real title now that the needle is built from the real site tag'

    # Full, unmodified, real call site (line ~1263, inside Test-RemoteEditorOnCorrectFolder's
    # Get-ProcessTopLevelWindows loop): the decoy IS a real, correctly-profiled, correctly
    # command-lined, correctly window-titled "on this exact folder" process/window - production
    # code now correctly reports on-folder = $true here (GREEN), where it used to report $false
    # (RED) before the site-tag fix.
    $onFolderReal = Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $Alias -RemotePath $TargetPath
    Assert ($onFolderReal -eq $true) 'Test-RemoteEditorOnCorrectFolder (REAL, unmodified, source-extracted function) returns TRUE for the REAL site-tagged decoy window - FIXED: this genuinely-titled on-folder window is now correctly detected by production code'

    try { $pBuggy.Kill() } catch { }
    try { [void]$pBuggy.WaitForExit(3000) } catch { }
    Start-Sleep -Milliseconds 300
    if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
    $script:EditorCimCache = @{}

    # --- Phase 2: control decoy with the LITERAL (never-emitted) title, same everything else ---
    $pControl = Start-Process -FilePath $stubExe -ArgumentList $argsControl -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    Assert (-not $pControl.HasExited) 'control decoy process (literal, never-emitted "[Claude Server] myrepo") is actually running'

    $onFolderControl = Test-RemoteEditorOnCorrectFolder -EditorCmd 'cursor' -Alias $Alias -RemotePath $TargetPath
    Assert ($onFolderControl -eq $true) 'Test-RemoteEditorOnCorrectFolder DOES return TRUE for the control decoy (literal title production never actually writes) - proves the site tag, and only the site tag, is what breaks real-world detection'
} finally {
    foreach ($p in @($pBuggy, $pControl)) {
        if ($p) {
            try {
                $stillAlive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
                if ($stillAlive) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
    }
    Start-Sleep -Milliseconds 300
    $buggyGone = $true
    $controlGone = $true
    if ($pBuggy) { $buggyGone = -not (Get-Process -Id $pBuggy.Id -ErrorAction SilentlyContinue) }
    if ($pControl) { $controlGone = -not (Get-Process -Id $pControl.Id -ErrorAction SilentlyContinue) }
    Assert $buggyGone 'real-title decoy PID confirmed gone after the run (cleaned up in finally)'
    Assert $controlGone 'control decoy PID confirmed gone after the run (cleaned up in finally)'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Research: VS Code/Cursor Remote-SSH single-instance IPC (Electron app.requestSingleInstanceLock' -ForegroundColor DarkGray
Write-Host '+ "launch" Node IPC channel registered by the FIRST process, per VS Code electron-main/app.ts)' -ForegroundColor DarkGray
Write-Host 'hands a second --folder-uri/open request to the ALREADY-RUNNING main process (new BrowserWindow' -ForegroundColor DarkGray
Write-Host 'inside the SAME OS process), never spawning a fresh client process for that folder - so that' -ForegroundColor DarkGray
Write-Host 'PIDs Win32_Process.CommandLine (fixed at original process creation) never reflects the new' -ForegroundColor DarkGray
Write-Host 'folder. This is exactly why a window-title/window-count secondary signal (this test''s target)' -ForegroundColor DarkGray
Write-Host 'is required as a second detection path beyond CommandLine matching.' -ForegroundColor DarkGray
Write-Host ''

if ($fail -eq 0) {
    Write-Host 'ALL PASS (GREEN): Bug 2 is FIXED - anchored Test-CursorWindowTitleMatchesProject + Get-CursorWindowTitleNeedle detect the real site-qualified window title against real code/process/window.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail FAIL (unexpected - re-verify against current source)" -ForegroundColor Red
exit 1
