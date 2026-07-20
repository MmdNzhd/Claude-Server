from pathlib import Path
root = Path(__file__).resolve().parents[2]

# --- connect.sh: if only Windows leftovers, auto-offer add like empty list ---
cs = root / "scripts/client/mac/connect.sh"
t = cs.read_text(encoding="utf-8")
old = '''        if [ -z "$mounts_visible" ] && [ "$hidden_count" -gt 0 ]; then
            if [ "${GIT_MODE_LAPTOP_OS:-mac}" = "mac" ]; then
                printf '    \\033[0;90mNo Mac projects (%s Windows-only on server).\\033[0m\\n\\n' "$hidden_count"
            else
                printf '    \\033[0;90mNo PC projects (%s Mac-only on server).\\033[0m\\n\\n' "$hidden_count"
            fi
        fi

        show_mounts "$mounts_visible"
'''
new = '''        if [ -z "$mounts_visible" ] && [ "$hidden_count" -gt 0 ]; then
            if [ "${GIT_MODE_LAPTOP_OS:-mac}" = "mac" ]; then
                printf '    \\033[0;33mNo Mac projects yet (%s old Windows paths ignored).\\033[0m\\n' "$hidden_count"
            else
                printf '    \\033[0;33mNo PC projects yet (%s old Mac paths ignored).\\033[0m\\n' "$hidden_count"
            fi
            printf '    \\033[0;36mAdd a folder from this laptop...\\033[0m\\n\\n'
            do_add
            if [ -n "$_added_path" ]; then
                go_path="$_added_path"; go_id="$_added_id"
                break
            fi
            mounts_raw="$(load_mounts)"
            mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
            hidden_count="$(count_skipped_mounts_for_laptop "$mounts_raw")"
            continue
        fi

        show_mounts "$mounts_visible"
'''
if old not in t:
    raise SystemExit('connect.sh block not found')
t = t.replace(old, new, 1)

old_fail = '''step "Laptop SSH access"
if ensure_laptop_ssh_key "$PUB_B"; then
    step_ok
else
    step_fail "will retry on mount - enable Remote Login for this user if needed"
fi'''
new_fail = '''step "Laptop SSH access"
if ensure_laptop_ssh_key "$PUB_B"; then
    step_ok
else
    step_fail "will retry on mount"
    warn "Mac: System Settings -> General -> Sharing -> Remote Login = ON"
    warn "     Allow access for user: ${LAPTOP_USER:-$(whoami)}  (or All users)"
fi'''
if old_fail not in t:
    raise SystemExit('fail block not found')
t = t.replace(old_fail, new_fail, 1)
cs.write_text(t, encoding="utf-8", newline="\n")
print('connect.sh ok')

# --- git-mode: purge incompatible mount confs on server (self-heal leftovers) ---
gm = root / "scripts/client/git-mode.sh"
g = gm.read_text(encoding="utf-8")
# insert after filter_mounts_for_laptop function area - add purge helper before mount_list_step_label
marker = "mount_list_step_label() {"
helper = r'''purge_incompatible_server_mounts() {
    # Remove mount configs whose laptop path cannot work on this OS (e.g. D:/ on Mac).
    local os="${1:-${GIT_MODE_LAPTOP_OS:-}}" raw line mid mrpath n=0
    [ -n "$os" ] || return 0
    raw="$(sshx "$CM list 2>/dev/null" 2>/dev/null || true)"
    [ -n "$raw" ] || return 0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS='|' read -r mid _label mrpath _lpath <<< "$line"
        [ -n "$mid" ] && [ -n "$mrpath" ] || continue
        if laptop_rpath_compatible "$mrpath" "$os"; then
            continue
        fi
        sshx "$CM remove '$mid' 2>/dev/null" >/dev/null 2>&1 || \
            sshx "rm -f \"\$HOME/.claude-mounts.d/${mid}.conf\"" >/dev/null 2>&1 || true
        n=$((n + 1))
    done <<< "$raw"
    [ "$n" -gt 0 ] && warn "Removed $n leftover project(s) incompatible with this laptop OS."
    return 0
}

'''
if "purge_incompatible_server_mounts()" not in g:
    if marker not in g:
        raise SystemExit('marker missing')
    g = g.replace(marker, helper + marker, 1)
    gm.write_text(g, encoding="utf-8", newline="\n")
    print('purge helper ok')
else:
    print('purge already present')

# call purge once after load in connect - actually call before filter when hidden
# Add to connect.sh after load_mounts
cs_t = cs.read_text(encoding="utf-8")
needle = '''    step "Loading projects"
    mounts_raw="$(load_mounts)"
    mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
'''
repl = '''    step "Loading projects"
    mounts_raw="$(load_mounts)"
    if [ "${GIT_MODE_LAPTOP_OS:-}" = "mac" ] || [ "${GIT_MODE_LAPTOP_OS:-}" = "windows" ]; then
        if [ "$(count_skipped_mounts_for_laptop "$mounts_raw" 2>/dev/null || echo 0)" -gt 0 ]; then
            purge_incompatible_server_mounts "${GIT_MODE_LAPTOP_OS}" 2>/dev/null || true
            mounts_raw="$(load_mounts)"
        fi
    fi
    mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
'''
# Wait - we already replaced connect.sh content into t and wrote it. Re-read.
cs_t = Path(cs).read_text(encoding="utf-8")
if "purge_incompatible_server_mounts" not in cs_t:
    if needle not in cs_t:
        raise SystemExit('load block missing')
    cs.write_text(cs_t.replace(needle, repl, 1), encoding="utf-8", newline="\n")
    print('connect purge call ok')
else:
    print('connect purge call already')

# bump 15 -> 16
for rel in [
    "scripts/client/mac/connect.sh",
    "scripts/client/windows/connect.ps1",
    "scripts/client/mac/connect-version.txt",
    "scripts/client/windows/connect-version.txt",
]:
    p = root / rel
    x = p.read_text(encoding="utf-8").replace("20260717.15", "20260717.16")
    if "20260717.16" not in x:
        raise SystemExit(f'ver {rel}')
    p.write_text(x, encoding="utf-8", newline="\n")
print('version 16')
print('done')
