# test-title-project-match.ps1 - window-title -> project match must be template-anchored, never a
# bare substring. Callers: scripts/client/tests/run-all.ps1
#
# Live repro 2026-07-25 (project=smart never opened): the server-profile window title template is
# "[Claude Server Smart] <rootName>" - "Smart" is the SITE TAG. The old title heuristic did
# ($title -match $rootName) anywhere in the title, so a project literally named "smart" matched the
# "Smart" inside the tag on EVERY open window -> on_folder=True -> EDITOR_LAUNCH_SKIP
# reason=known_on_folder -> smart was never opened (an unrelated window got foregrounded instead).
# A bare/word-boundary substring also cross-matched prefix siblings ("smart" in "smartdesk", "ai" in
# "ai-gap-summay"). Test-CursorWindowTitleMatchesProject anchors the root to the exact template
# position with a trailing non-path boundary. This test locks that behavior.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

. (Get-ClientFile 'editor-launch.ps1')

Write-Host ''
Write-Host '=== Window-title -> project match (anchored) ===' -ForegroundColor Cyan
Write-Host ''

Assert (Get-Command Test-CursorWindowTitleMatchesProject -ErrorAction SilentlyContinue) 'Test-CursorWindowTitleMatchesProject defined'

$tag = 'Claude Server Smart'
$alias = [regex]::Escape('claude-server')

# --- Positive: real match at the template-anchored position ---------------------------------------
Assert (Test-CursorWindowTitleMatchesProject -Title "[$tag] smart" -RootName 'smart' -TitleTag $tag) `
    'project smart matches its own "[Claude Server Smart] smart" window'
Assert (Test-CursorWindowTitleMatchesProject -Title "file.ts - [$tag] smart" -RootName 'smart' -TitleTag $tag) `
    'dirty/editor prefix before the tag still matches (root at end)'
Assert (Test-CursorWindowTitleMatchesProject -Title "[$tag] smartdesk" -RootName 'smartdesk' -TitleTag $tag) `
    'project smartdesk matches its own window'
Assert (Test-CursorWindowTitleMatchesProject -Title "[$tag] ai-gap-summay" -RootName 'ai-gap-summay' -TitleTag $tag) `
    'hyphenated project ai-gap-summay matches its own window'

# --- Negative: the site-tag collision that broke project "smart" ---------------------------------
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag]" -RootName 'smart' -TitleTag $tag)) `
    'project smart does NOT match a bare "[Claude Server Smart]" (agent-home) window (site-tag collision)'
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag] deploy" -RootName 'smart' -TitleTag $tag)) `
    'project smart does NOT match an unrelated "[Claude Server Smart] deploy" window'
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag] smartdesk" -RootName 'smart' -TitleTag $tag)) `
    'project smart does NOT match "smartdesk" (prefix sibling)'

# --- Negative: hyphen prefix sibling (ai vs ai-gap-summay) ----------------------------------------
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag] ai-gap-summay" -RootName 'ai' -TitleTag $tag)) `
    'project ai does NOT match "ai-gap-summay" (hyphen boundary would false-match a bare \b)'

# --- Cursor default Remote-SSH title fallback -----------------------------------------------------
Assert (Test-CursorWindowTitleMatchesProject -Title 'smart [SSH: claude-server] - Cursor' -RootName 'smart' -TitleTag $tag -AliasNeedleEscaped $alias) `
    'default SSH title "smart [SSH: claude-server]" matches project smart'
Assert (-not (Test-CursorWindowTitleMatchesProject -Title 'smartdesk [SSH: claude-server] - Cursor' -RootName 'smart' -TitleTag $tag -AliasNeedleEscaped $alias)) `
    'default SSH title "smartdesk [SSH: ...]" does NOT match project smart'

# --- Site-tag + SSH collision (live 2026-07-25): the CUSTOM title is "[Claude Server Smart] <root> [SSH: <alias>]".
# Searching project "smart" must NOT match the "Smart" inside the SITE TAG and then skip across a
# DIFFERENT root to the [SSH:] marker. Old greedy [^\[]* did exactly that -> on_folder=True for "smart"
# with no smart window open -> connect skipped the launch and "smart" never opened. \s* anchors the root
# immediately before [SSH:].
Assert (-not (Test-CursorWindowTitleMatchesProject -Title "[$tag] refactoreoldclub [SSH: claude-server]" -RootName 'smart' -TitleTag $tag -AliasNeedleEscaped $alias)) `
    'site-qualified title with a DIFFERENT root + [SSH:] does NOT match project smart (site-tag "Smart" must not reach the marker)'
Assert (Test-CursorWindowTitleMatchesProject -Title "[$tag] refactoreoldclub [SSH: claude-server]" -RootName 'refactoreoldclub' -TitleTag $tag -AliasNeedleEscaped $alias) `
    'site-qualified title still matches its OWN root (refactoreoldclub) via the anchored template check'
Assert (Test-CursorWindowTitleMatchesProject -Title "[$tag] smart [SSH: claude-server]" -RootName 'smart' -TitleTag $tag -AliasNeedleEscaped $alias) `
    'site-qualified title "[Claude Server Smart] smart [SSH:...]" matches project smart (real match)'

# --- Agent-home helper no longer spoofed by the site tag -----------------------------------------
# (Test-CursorWindowTitleIsAgentHome only flags explicit "Cursor Agents"/"agent home" titles; the
# early ProjectRootName short-circuit must NOT fire off the "Smart" site tag for project smart.)
Assert (Test-CursorWindowTitleIsAgentHome -Title 'Cursor Agents' -ProjectRootName 'smart') `
    'explicit "Cursor Agents" title is agent home even for project smart'
Assert (-not (Test-CursorWindowTitleIsAgentHome -Title "[$tag] smart" -ProjectRootName 'smart')) `
    '"[Claude Server Smart] smart" is a real project window, not agent home'

# --- Source guard: the buggy bare-substring title match is gone -----------------------------------
$src = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert (-not ($src -match '\$title -match \$rootNeedle -and')) `
    'no bare ($title -match $rootNeedle) title check remains in editor-launch.ps1'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
