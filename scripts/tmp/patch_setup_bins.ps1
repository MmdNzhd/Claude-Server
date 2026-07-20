$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

# --- 1) laptop-exec-setup.sh: install self + automount in _ensure_user ---
$setup = Join-Path $root 'scripts\server\laptop-exec-setup.sh'
$c = [IO.File]::ReadAllText($setup)
$old = @'
_ensure_user() {
    [ -f "$GOLDEN_BIN" ] || return 0
    mkdir -p "$HOME/.local/bin" "$HOME/.cursor/rules" "$HOME/.cursor/skills/laptop-exec"
    if [ ! -f "$HOME/.local/bin/laptop-exec" ] || [ "$GOLDEN_BIN" -nt "$HOME/.local/bin/laptop-exec" ]; then
        install -m 755 "$GOLDEN_BIN" "$HOME/.local/bin/laptop-exec"
    fi
    if [ -f "$GOLDEN_RULE" ]; then
        install -m 644 "$GOLDEN_RULE" "$HOME/.cursor/rules/laptop-exec.mdc"
    fi
    if [ -f "$GOLDEN_SKILL" ]; then
        install -m 644 "$GOLDEN_SKILL" "$HOME/.cursor/skills/laptop-exec/SKILL.md"
    fi
    _ensure_user_hooks
    _ensure_cursor_git_off
    if [ -x "$GOLDEN_HEAL" ]; then
        install -m 755 "$GOLDEN_HEAL" "$HOME/.local/bin/claude-self-heal"
        "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true
    fi
}
'@
$new = @'
_ensure_user() {
    [ -f "$GOLDEN_BIN" ] || return 0
    mkdir -p "$HOME/.local/bin" "$HOME/.cursor/rules" "$HOME/.cursor/skills/laptop-exec"
    if [ ! -f "$HOME/.local/bin/laptop-exec" ] || [ "$GOLDEN_BIN" -nt "$HOME/.local/bin/laptop-exec" ]; then
        install -m 755 "$GOLDEN_BIN" "$HOME/.local/bin/laptop-exec"
    fi
    # Keep setup itself in PATH so heal/audit/login can re-run without relying only on /usr/local/bin.
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        if [ ! -f "$HOME/.local/bin/laptop-exec-setup" ] || [ /usr/local/bin/laptop-exec-setup -nt "$HOME/.local/bin/laptop-exec-setup" ]; then
            install -m 755 /usr/local/bin/laptop-exec-setup "$HOME/.local/bin/laptop-exec-setup"
        fi
    fi
    if [ -x /usr/local/bin/claude-automount ]; then
        if [ ! -f "$HOME/.local/bin/claude-automount" ] || [ /usr/local/bin/claude-automount -nt "$HOME/.local/bin/claude-automount" ]; then
            install -m 755 /usr/local/bin/claude-automount "$HOME/.local/bin/claude-automount"
        fi
    fi
    if [ -f "$GOLDEN_RULE" ]; then
        install -m 644 "$GOLDEN_RULE" "$HOME/.cursor/rules/laptop-exec.mdc"
    fi
    if [ -f "$GOLDEN_SKILL" ]; then
        install -m 644 "$GOLDEN_SKILL" "$HOME/.cursor/skills/laptop-exec/SKILL.md"
    fi
    _ensure_user_hooks
    _ensure_cursor_git_off
    if [ -x "$GOLDEN_HEAL" ]; then
        install -m 755 "$GOLDEN_HEAL" "$HOME/.local/bin/claude-self-heal"
        "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true
    fi
}
'@
if ($c -notlike "*$($old.Substring(0,40))*") { throw 'setup _ensure_user block not found' }
# Use exact replace via markers
if ($c -notmatch [regex]::Escape('Keep setup itself in PATH')) {
  if (-not $c.Contains('_ensure_user() {')) { throw 'no _ensure_user' }
  $idx = $c.IndexOf('_ensure_user() {')
  $end = $c.IndexOf('_ensure_project_skill() {', $idx)
  if ($end -lt 0) { throw 'end marker missing' }
  $c = $c.Substring(0, $idx) + $new.TrimEnd() + "`n`n" + $c.Substring($end)
  [IO.File]::WriteAllText($setup, $c)
  Write-Host 'OK patched laptop-exec-setup.sh'
} else { Write-Host 'SKIP setup already patched' }

# --- 2) deploy-laptop-exec.sh: install setup+automount into user bins ---
$dep = Join-Path $root 'scripts\server\commands\deploy-laptop-exec.sh'
$d = [IO.File]::ReadAllText($dep)
$needle = @'
  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"
  [ -f /usr/local/bin/claude-self-heal ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" && sed -i 's/\r$//' "$h/.local/bin/claude-self-heal" 2>/dev/null || true
  sed -i 's/\r$//' "$h/.local/bin/laptop-exec" 2>/dev/null || true
'@
$repl = @'
  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"
  [ -f /usr/local/bin/laptop-exec-setup ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec-setup "$h/.local/bin/laptop-exec-setup" && sed -i 's/\r$//' "$h/.local/bin/laptop-exec-setup" 2>/dev/null || true
  [ -f /usr/local/bin/claude-automount ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-automount "$h/.local/bin/claude-automount" && sed -i 's/\r$//' "$h/.local/bin/claude-automount" 2>/dev/null || true
  [ -f /usr/local/bin/claude-self-heal ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" && sed -i 's/\r$//' "$h/.local/bin/claude-self-heal" 2>/dev/null || true
  sed -i 's/\r$//' "$h/.local/bin/laptop-exec" 2>/dev/null || true
'@
if ($d -match 'install -m 755 -o "\$u" -g "\$u" /usr/local/bin/laptop-exec-setup') {
  Write-Host 'SKIP deploy already patched'
} elseif ($d.Contains($needle)) {
  $d = $d.Replace($needle, $repl)
  [IO.File]::WriteAllText($dep, $d)
  Write-Host 'OK patched deploy-laptop-exec.sh'
} else { throw 'deploy needle not found' }

# --- 3) claude-self-heal.sh: refresh missing bins from /usr/local/bin ---
$heal = Join-Path $root 'scripts\server\claude-self-heal.sh'
$h = [IO.File]::ReadAllText($heal)
if ($h -match '_heal_missing_user_bins') {
  Write-Host 'SKIP heal already has _heal_missing_user_bins'
} else {
  $insertAfter = '_heal_bin_crlf_all() {'
  if (-not $h.Contains($insertAfter)) { throw 'heal _heal_bin_crlf_all missing' }
  $fn = @'

# ---------------------------------------------------------------------------
# 2c) Ensure critical user bins exist (refresh from /usr/local/bin)
# ---------------------------------------------------------------------------
_heal_missing_user_bins() {
    local name sys dst
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    for name in laptop-exec laptop-exec-setup claude-self-heal claude-automount claude-mount; do
        sys="/usr/local/bin/$name"
        [ -x "$sys" ] || continue
        dst="$HOME/.local/bin/$name"
        if [ ! -f "$dst" ] || [ "$sys" -nt "$dst" ] || grep -q $'\r' "$dst" 2>/dev/null; then
            cp -f "$sys" "$dst" 2>/dev/null || true
            chmod 755 "$dst" 2>/dev/null || true
            sed -i 's/\r$//' "$dst" 2>/dev/null || true
            _log "refreshed $name"
        fi
    done
}

'@
  # Insert function before _heal_bin_crlf_all, and call it from main
  $h = $h.Replace("# ---------------------------------------------------------------------------`n# 2b) Strip CRLF on all user claude/laptop bins (Windows scp often leaves CR)`n# ---------------------------------------------------------------------------`n_heal_bin_crlf_all() {", ($fn.TrimStart() + "`n# ---------------------------------------------------------------------------`n# 2b) Strip CRLF on all user claude/laptop bins (Windows scp often leaves CR)`n# ---------------------------------------------------------------------------`n_heal_bin_crlf_all() {")
  if ($h -notmatch '_heal_missing_user_bins') { throw 'insert failed' }
  # Wire call: after _heal_laptop_exec_crlf and before/with _heal_bin_crlf_all
  if ($h -match '_heal_laptop_exec_crlf\n_heal_bin_crlf_all') {
    $h = $h -replace '_heal_laptop_exec_crlf\r?\n_heal_bin_crlf_all', "_heal_laptop_exec_crlf`n_heal_missing_user_bins`n_heal_bin_crlf_all"
  } elseif ($h -match '_heal_bin_crlf_all\n_heal_cursor_git_off') {
    $h = $h -replace '_heal_bin_crlf_all\r?\n_heal_cursor_git_off', "_heal_missing_user_bins`n_heal_bin_crlf_all`n_heal_cursor_git_off"
  } else {
    # find main call section
    $m = [regex]::Match($h, '(?m)^_heal_bin_crlf_all$')
    if (-not $m.Success) { throw 'cannot find _heal_bin_crlf_all call site' }
    $h = $h.Insert($m.Index, "_heal_missing_user_bins`n")
  }
  [IO.File]::WriteAllText($heal, $h)
  Write-Host 'OK patched claude-self-heal.sh'
}

Write-Host 'PATCH_DONE'
