from pathlib import Path

root = Path(r"D:\Smart\Claude-Code-Server")

# 1) laptop-exec-setup.sh
setup = root / "scripts/server/laptop-exec-setup.sh"
c = setup.read_text(encoding="utf-8")
if "Keep setup itself in PATH" not in c:
    start = c.index("_ensure_user() {")
    end = c.index("_ensure_project_skill() {", start)
    new = '''_ensure_user() {
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

'''
    c = c[:start] + new + c[end:]
    setup.write_text(c, encoding="utf-8", newline="\n")
    print("OK patched laptop-exec-setup.sh")
else:
    print("SKIP setup already patched")

# 2) deploy-laptop-exec.sh
dep = root / "scripts/server/commands/deploy-laptop-exec.sh"
d = dep.read_text(encoding="utf-8")
if 'install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec-setup' in d:
    print("SKIP deploy already patched")
else:
    needle = '''  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"
  [ -f /usr/local/bin/claude-self-heal ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" && sed -i 's/\\r$//' "$h/.local/bin/claude-self-heal" 2>/dev/null || true
  sed -i 's/\\r$//' "$h/.local/bin/laptop-exec" 2>/dev/null || true
'''
    repl = '''  install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec "$h/.local/bin/laptop-exec"
  [ -f /usr/local/bin/laptop-exec-setup ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/laptop-exec-setup "$h/.local/bin/laptop-exec-setup" && sed -i 's/\\r$//' "$h/.local/bin/laptop-exec-setup" 2>/dev/null || true
  [ -f /usr/local/bin/claude-automount ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-automount "$h/.local/bin/claude-automount" && sed -i 's/\\r$//' "$h/.local/bin/claude-automount" 2>/dev/null || true
  [ -f /usr/local/bin/claude-self-heal ] && install -m 755 -o "$u" -g "$u" /usr/local/bin/claude-self-heal "$h/.local/bin/claude-self-heal" && sed -i 's/\\r$//' "$h/.local/bin/claude-self-heal" 2>/dev/null || true
  sed -i 's/\\r$//' "$h/.local/bin/laptop-exec" 2>/dev/null || true
'''
    if needle not in d:
        raise SystemExit("deploy needle not found")
    dep.write_text(d.replace(needle, repl), encoding="utf-8", newline="\n")
    print("OK patched deploy-laptop-exec.sh")

# 3) claude-self-heal.sh
heal = root / "scripts/server/claude-self-heal.sh"
h = heal.read_text(encoding="utf-8")
if "_heal_missing_user_bins" in h:
    print("SKIP heal already patched")
else:
    marker = "# ---------------------------------------------------------------------------\n# 2b) Strip CRLF on all user claude/laptop bins (Windows scp often leaves CR)\n# ---------------------------------------------------------------------------\n_heal_bin_crlf_all() {"
    fn = '''# ---------------------------------------------------------------------------
# 2c) Ensure critical user bins exist (refresh from /usr/local/bin)
# ---------------------------------------------------------------------------
_heal_missing_user_bins() {
    local name sys dst
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    for name in laptop-exec laptop-exec-setup claude-self-heal claude-automount claude-mount; do
        sys="/usr/local/bin/$name"
        [ -x "$sys" ] || continue
        dst="$HOME/.local/bin/$name"
        if [ ! -f "$dst" ] || [ "$sys" -nt "$dst" ] || grep -q $'\\r' "$dst" 2>/dev/null; then
            cp -f "$sys" "$dst" 2>/dev/null || true
            chmod 755 "$dst" 2>/dev/null || true
            sed -i 's/\\r$//' "$dst" 2>/dev/null || true
            _log "refreshed $name"
        fi
    done
}

'''
    if marker not in h:
        raise SystemExit("heal marker not found")
    h = h.replace(marker, fn + marker, 1)
    # call site
    call = "_heal_bin_crlf_all\n"
    if call not in h:
        raise SystemExit("heal call site not found")
    # Only insert before the first standalone call (after function defs). Find main section.
    # Prefer inserting right before the call that follows _heal_laptop_exec_crlf
    target = "_heal_laptop_exec_crlf\n_heal_bin_crlf_all\n"
    if target in h:
        h = h.replace(target, "_heal_laptop_exec_crlf\n_heal_missing_user_bins\n_heal_bin_crlf_all\n", 1)
    else:
        # fallback: first occurrence of bare call after function definition end
        idx = h.rfind("_heal_bin_crlf_all() {")
        idx2 = h.find("\n_heal_bin_crlf_all\n", idx)
        if idx2 < 0:
            raise SystemExit("cannot wire heal call")
        h = h[: idx2 + 1] + "_heal_missing_user_bins\n" + h[idx2 + 1 :]
    heal.write_text(h, encoding="utf-8", newline="\n")
    print("OK patched claude-self-heal.sh")

print("PATCH_DONE")
