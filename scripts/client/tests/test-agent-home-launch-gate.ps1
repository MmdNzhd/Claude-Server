# test-agent-home-launch-gate.ps1 - guards the 2026-07-25 "opening matters, not the title" launch fixes.
# Callers: scripts/client/tests/run-all.ps1
#
# Live regressions this locks (all hit 2026-07-25, project windows failed to open / connect looped on
# "Cursor drifted to Agent/home"):
#   1) window.title here-string bug: Initialize-CursorServerProfile built the title inside a
#      double-quoted here-string, so PowerShell expanded ${dirty}/${activeEditorShort}/${separator}/
#      ${rootName} to EMPTY. settings.json became "[Claude Server Smart] " with NO folder name, so
#      remote window titles never showed the project and title-based detection was blind.
#   2) --remote main process misread as agent-home: Test-RemoteEditorInAgentHome flagged any main
#      process whose cmd lacked 'folder-uri' as agent-home. After reordering strategies to --remote
#      first, the cold-start cmd had --remote (no folder-uri) -> agent_home=True forever -> every
#      launch's success gate (-not agent_home) rejected a window that actually opened.
#   3) standalone "Cursor Agents" window poisoned on_folder: Test-RemoteEditorOnCorrectFolder had a
#      GLOBAL "if (Test-RemoteEditorInAgentHome) return false" short-circuit, so on_folder was false
#      for EVERY project whenever a normal Cursor 3.x Agents window was open.
#   4) success gate vetoed real opens: it required -not $afterAgent even when $afterFolder was true.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Write-ConnectLog { param($m, $l) }
$elPath = Get-ClientFile 'editor-launch.ps1'
. $elPath
$src = Get-Content $elPath -Raw

Write-Host ''
Write-Host '=== Agent-home / launch-gate ("opening matters") ===' -ForegroundColor Cyan
Write-Host ''

# --- 1) window.title template keeps the literal VS Code ${...} tokens --------------------------------
Assert (Get-Command Get-CursorServerWindowTitleTemplate -ErrorAction SilentlyContinue) 'Get-CursorServerWindowTitleTemplate defined'
$tpl = Get-CursorServerWindowTitleTemplate -TitleTag 'Claude Server Smart'
Assert ($tpl -match '\$\{rootName\}') 'title template contains literal ${rootName} (not PowerShell-expanded to empty)'
Assert ($tpl -match '\$\{dirty\}' -and $tpl -match '\$\{activeEditorShort\}' -and $tpl -match '\$\{separator\}') 'title template keeps ${dirty}/${activeEditorShort}/${separator} literals'
Assert ($tpl -match '\[Claude Server Smart\]') 'title template embeds the site tag'
# The Cursor profile writer must build window.title via the helper (concatenation), NOT inline inside a
# double-quoted here-string (which is exactly what expanded ${rootName} to empty). The VS Code writer
# (Initialize-CodeServerProfile) already uses a single-quoted @'...'@ here-string, which is also safe.
Assert ($src -match '\$titleTemplate = Get-CursorServerWindowTitleTemplate') 'Cursor profile builds title via the helper variable (no inline double-quoted expansion)'
Assert ($src -match '"window\.title": "\$titleTemplate"') 'Cursor profile here-string interpolates the prebuilt $titleTemplate (single interpolation, tokens stay literal)'

# --- 2) Repair fixes an old broken profile settings.json (missing ${rootName}) -----------------------
Assert (Get-Command Repair-CursorServerWindowTitle -ErrorAction SilentlyContinue) 'Repair-CursorServerWindowTitle defined'
$tmp = Join-Path $env:TEMP ("agenthome-test-{0}.json" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
try {
    # broken form produced by the old here-string bug
    '{ "window.title": "[Claude Server Smart] ", "editor.fontSize": 14 }' | Set-Content -LiteralPath $tmp -Encoding UTF8
    $changed = Repair-CursorServerWindowTitle -SettingsPath $tmp -TitleTag 'Claude Server Smart'
    $after = Get-Content -LiteralPath $tmp -Raw
    Assert ($changed) 'repair reports it changed a broken window.title'
    Assert ($after -match '\$\{rootName\}') 'repaired settings.json now has ${rootName}'
    Assert ($after -match 'editor\.fontSize') 'repair preserved other settings'
    # idempotent: a correct file is left alone
    $changed2 = Repair-CursorServerWindowTitle -SettingsPath $tmp -TitleTag 'Claude Server Smart'
    Assert (-not $changed2) 'repair is idempotent (no-op when ${rootName} already present)'
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

# --- 3) Test-RemoteEditorInAgentHome treats --remote / ssh-remote+ / vscode-remote:// as a folder ----
Assert ($src -match '\$opensFolder\s*=') 'agent-home check computes $opensFolder (folder-uri OR --remote OR ssh-remote+)'
Assert ($src -match "opensFolder[\s\S]{0,120}--remote") 'agent-home $opensFolder includes --remote'
Assert ($src -match "opensFolder[\s\S]{0,160}ssh-remote\\\+") 'agent-home $opensFolder includes ssh-remote+'
Assert ($src -notmatch "if \(\`\$cmd -notmatch 'folder-uri'\) \{\s*\r?\n\s*\`\$title = ''") 'old bare "cmd lacks folder-uri => agent-home" heuristic removed'

# --- 4) on_folder has NO global agent-home short-circuit --------------------------------------------
Assert ($src -notmatch 'if \(Test-RemoteEditorInAgentHome -RemotePath \$RemotePath\) \{ return \$false \}') 'on_folder no longer globally short-circuits on Test-RemoteEditorInAgentHome'

# --- 5) success gate: on_folder ONLY (unified with Confirm; window-count is promising only) ---------
Assert ($src -match 'if \(\$afterFolder\) \{') '$afterFolder alone marks launch OK (standalone Agents window cannot veto a real folder open)'
Assert ($src -match 'LAUNCH_OK: strategy=.*reason=on_folder') 'LAUNCH_OK reason is on_folder'
Assert ($src -match 'LAUNCH_PROMISING:.*window_count_increased_no_title_match') 'window-count is promising only (does not return true)'
Assert ($src -notmatch '\$launchOk = \$true; \$okReason = ''window_count_increased_no_title_match''') 'Launch no longer returns true on window_count alone (P0.4)'
Assert ($src -notmatch 'if \(\(\$afterFolder -or \$windowCountIncreased\) -and -not \$afterAgent\)') 'old combined gate (afterFolder OR wincount) AND not agent removed'

# --- 6) entry skip gated on on_folder alone ---------------------------------------------------------
Assert ($src -match 'if \(\$onFolder\) \{[\s\S]{0,700}LAUNCH_SKIP') 'entry skip gated on $onFolder alone'

# --- 7) warm handoff: remote + remote-classic + long poll (same-window title update needs time) ------
Assert ($src -match 'WarmHandoff') 'Get-RemoteEditorLaunchStrategies accepts -WarmHandoff'
Assert ($src -match 'if \(\$WarmHandoff\)') 'warm handoff returns early (no folder-uri cascade)'
Assert ($src -match 'elseif \(\$attempt -eq 1 -and \$useNewWindow -and \$profileProcCount -gt 0\) \{ 80 \}') 'warm attempt-1 poll ceiling is 80 ticks (20s) for Remote-SSH title settle'
Assert ($src -match 'elseif \(\$attempt -eq 1\) \{ 48 \}') 'cold attempt-1 poll ceiling is 48 ticks (12s; was 3s premature cascade)'
Assert ($src -match 'LAUNCH_GRACE: warm handoff') 'post-exhaustion warm grace wait for late on_folder'

# --- 8) session presence uses multi-window on_folder (not MainWindowTitle-only) ---------------------
Assert ($src -match 'function Get-RemoteEditorSessionPresence[\s\S]{0,900}Test-RemoteEditorOnCorrectFolder') 'Get-RemoteEditorSessionPresence delegates OnFolder to Test-RemoteEditorOnCorrectFolder'
Assert ($src -notmatch 'function Get-RemoteEditorSessionPresence[\s\S]{0,500}if \(Test-RemoteEditorInAgentHome -RemotePath \$RemotePath\)') 'presence no longer short-circuits on global agent-home'

# --- 9) non-elevated launch uses Start-Process DIRECT, not cmd Quiet wrap ----------------------------
# Live 2026-07-25: Start-EditorProcessQuiet (cmd /C + >>log) breaks Electron warm IPC; Start-Process
# opens the folder in ~1s. Connect must use the direct path for the default (non-elevated) launch.
Assert ($src -match 'function Start-EditorProcessDirect') 'Start-EditorProcessDirect helper defined'
Assert ($src -match 'mode=non_elevated_direct') 'non-elevated path logs non_elevated_direct'
Assert ($src -match 'Start-EditorProcessDirect -FilePath \$FilePath -ArgumentList \$ArgumentList') 'non-elevated path calls Start-EditorProcessDirect'
# The Quiet wrap must NOT be the non-elevated primary path anymore.
Assert ($src -notmatch "mode=non_elevated exe=.*\r?\n\s*Start-EditorProcessQuiet") 'non-elevated path no longer calls Start-EditorProcessQuiet'
# Silence Cursor Electron/Node noise in the connect console without the cmd Quiet wrap.
Assert ($src -match 'ELECTRON_NO_ATTACH_CONSOLE') 'direct launch sets ELECTRON_NO_ATTACH_CONSOLE (no parent-console attach)'
Assert ($src -match 'RedirectStandardError') 'direct launch redirects stderr away from connect console'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
