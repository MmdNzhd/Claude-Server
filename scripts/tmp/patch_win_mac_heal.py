from pathlib import Path

# --- self-heal: also CRLF-strip all claude bins + preserve LAPTOP_OS ---
heal = Path(r"D:\Smart\Claude-Code-Server\scripts\server\claude-self-heal.sh")
ht = heal.read_text(encoding="utf-8")
if "_heal_bin_crlf_all" not in ht:
    block = r'''
# ---------------------------------------------------------------------------
# 2b) Strip CRLF on all user claude/laptop bins (Windows scp often leaves CR)
# ---------------------------------------------------------------------------
_heal_bin_crlf_all() {
    local f
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    for f in \
        "$HOME/.local/bin/laptop-exec" \
        "$HOME/.local/bin/laptop-exec-setup" \
        "$HOME/.local/bin/claude-mount" \
        "$HOME/.local/bin/claude-automount" \
        "$HOME/.local/bin/claude-self-heal" \
        "$HOME/.local/bin/claude-git-setup" \
        "$HOME/.local/bin/claude-watchdog"
    do
        [ -f "$f" ] || continue
        if grep -q $'\r' "$f" 2>/dev/null; then
            sed -i 's/\r$//' "$f" 2>/dev/null || true
            chmod 755 "$f" 2>/dev/null || true
            _log "stripped CRLF $(basename "$f")"
        fi
    done
}

'''
    ht = ht.replace(
        "_heal_laptop_exec_crlf\n_heal_cursor_git_off\n_heal_remove_shim\n_heal_stale_mounts",
        "_heal_laptop_exec_crlf\n_heal_bin_crlf_all\n_heal_cursor_git_off\n_heal_remove_shim\n_heal_stale_mounts",
        1,
    )
    # insert function before _heal_cursor_git_off
    ht = ht.replace(
        "# ---------------------------------------------------------------------------\n# 3) Cursor/VS Code remote git OFF",
        block + "# ---------------------------------------------------------------------------\n# 3) Cursor/VS Code remote git OFF",
        1,
    )
    heal.write_text(ht, encoding="utf-8", newline="\n")
    print("self-heal CRLF-all patched")
else:
    print("self-heal already has bin crlf")

# --- Windows git-mode.ps1 ---
ps = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1")
pt = ps.read_text(encoding="utf-8")
old_ps = '''    $pairs = @(
        @{ Local = 'laptop-exec.sh'; Remote = '~/.local/bin/laptop-exec'; Exec = $true },
        @{ Local = 'laptop-exec-setup.sh'; Remote = '~/.local/bin/laptop-exec-setup'; Exec = $true },
        @{ Local = 'cursor-rules/laptop-exec.mdc'; Remote = '~/.cursor/rules/laptop-exec.mdc'; Exec = $false },
        @{ Local = 'skills/laptop-exec/SKILL.md'; Remote = '~/.cursor/skills/laptop-exec/SKILL.md'; Exec = $false },
        @{ Local = 'cursor-hooks/laptop-exec-guard.sh'; Remote = '~/.cursor/hooks/laptop-exec-guard.sh'; Exec = $true }
    )
    foreach ($p in $pairs) {
        $src = [System.IO.Path]::Combine($ServerDir, $p.Local)
        Push-RemoteUserFileIfChanged -LocalSrc $src -RemotePath $p.Remote -Alias $Alias -Executable:$p.Exec
    }
    if (Test-Path ([System.IO.Path]::Combine($ServerDir, 'laptop-exec-setup.sh'))) {
        SshX '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>$null | Out-Null
    }
}
'''
new_ps = '''    $pairs = @(
        @{ Local = 'laptop-exec.sh'; Remote = '~/.local/bin/laptop-exec'; Exec = $true },
        @{ Local = 'laptop-exec-setup.sh'; Remote = '~/.local/bin/laptop-exec-setup'; Exec = $true },
        @{ Local = 'claude-self-heal.sh'; Remote = '~/.local/bin/claude-self-heal'; Exec = $true },
        @{ Local = 'claude-automount.sh'; Remote = '~/.local/bin/claude-automount'; Exec = $true },
        @{ Local = 'cursor-rules/laptop-exec.mdc'; Remote = '~/.cursor/rules/laptop-exec.mdc'; Exec = $false },
        @{ Local = 'skills/laptop-exec/SKILL.md'; Remote = '~/.cursor/skills/laptop-exec/SKILL.md'; Exec = $false },
        @{ Local = 'cursor-hooks/laptop-exec-guard.sh'; Remote = '~/.cursor/hooks/laptop-exec-guard.sh'; Exec = $true }
    )
    foreach ($p in $pairs) {
        $src = [System.IO.Path]::Combine($ServerDir, $p.Local)
        Push-RemoteUserFileIfChanged -LocalSrc $src -RemotePath $p.Remote -Alias $Alias -Executable:$p.Exec
    }
    # Windows scp can leave CRLF — strip on server for Win+Mac users alike
    SshX "sed -i 's/\\r$//' ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.local/bin/claude-self-heal ~/.local/bin/claude-automount ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.local/bin/claude-self-heal ~/.local/bin/claude-automount 2>/dev/null; true" 2>$null | Out-Null
    if (Test-Path ([System.IO.Path]::Combine($ServerDir, 'laptop-exec-setup.sh'))) {
        SshX '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>$null | Out-Null
    }
    # Self-heal for both Windows and Mac laptop sessions (runs on Linux server)
    SshX '$HOME/.local/bin/claude-self-heal --quiet 2>/dev/null; /usr/local/bin/claude-self-heal --quiet 2>/dev/null; true' 2>$null | Out-Null
}
'''
if old_ps not in pt:
    raise SystemExit('ps1 bundle block not found')
ps.write_text(pt.replace(old_ps, new_ps, 1), encoding='utf-8', newline='\r\n')  # keep PS CRLF for Windows
print('git-mode.ps1 patched')

# --- Mac git-mode.sh ---
sh = Path(r"D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh")
st = sh.read_text(encoding="utf-8")
old_sh = '''push_laptop_exec_bundle() {
    local server_dir="$1"
    [ -n "$server_dir" ] || return 0
    push_remote_file_if_changed "$server_dir/laptop-exec.sh" '~/.local/bin/laptop-exec' || true
    push_remote_file_if_changed "$server_dir/laptop-exec-setup.sh" '~/.local/bin/laptop-exec-setup' || true
    push_remote_file_if_changed "$server_dir/cursor-rules/laptop-exec.mdc" '~/.cursor/rules/laptop-exec.mdc' || true
    push_remote_file_if_changed "$server_dir/skills/laptop-exec/SKILL.md" '~/.cursor/skills/laptop-exec/SKILL.md' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-guard.sh" '~/.cursor/hooks/laptop-exec-guard.sh' || true
    sshx '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' >/dev/null 2>&1 || true
}
'''
new_sh = '''push_laptop_exec_bundle() {
    local server_dir="$1"
    [ -n "$server_dir" ] || return 0
    push_remote_file_if_changed "$server_dir/laptop-exec.sh" '~/.local/bin/laptop-exec' || true
    push_remote_file_if_changed "$server_dir/laptop-exec-setup.sh" '~/.local/bin/laptop-exec-setup' || true
    push_remote_file_if_changed "$server_dir/claude-self-heal.sh" '~/.local/bin/claude-self-heal' || true
    push_remote_file_if_changed "$server_dir/claude-automount.sh" '~/.local/bin/claude-automount' || true
    push_remote_file_if_changed "$server_dir/cursor-rules/laptop-exec.mdc" '~/.cursor/rules/laptop-exec.mdc' || true
    push_remote_file_if_changed "$server_dir/skills/laptop-exec/SKILL.md" '~/.cursor/skills/laptop-exec/SKILL.md' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-guard.sh" '~/.cursor/hooks/laptop-exec-guard.sh' || true
    # chmod + CRLF strip (safe for Mac and Windows-origin bundles)
    sshx "chmod +x \$HOME/.local/bin/laptop-exec \$HOME/.local/bin/laptop-exec-setup \$HOME/.local/bin/claude-self-heal \$HOME/.local/bin/claude-automount 2>/dev/null; sed -i 's/\\r\$//' \$HOME/.local/bin/laptop-exec \$HOME/.local/bin/laptop-exec-setup \$HOME/.local/bin/claude-self-heal \$HOME/.local/bin/claude-automount \$HOME/.local/bin/claude-mount 2>/dev/null; true" >/dev/null 2>&1 || true
    sshx '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' >/dev/null 2>&1 || true
    # Self-heal for Mac and Windows laptop sessions (server-side)
    sshx '$HOME/.local/bin/claude-self-heal --quiet 2>/dev/null; /usr/local/bin/claude-self-heal --quiet 2>/dev/null; true' >/dev/null 2>&1 || true
}
'''
if old_sh not in st:
    raise SystemExit('sh bundle block not found')
# also chmod pattern for self-heal in push_remote_file
st2 = st.replace(old_sh, new_sh, 1)
st2 = st2.replace(
    "*/laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh)",
    "*/laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh|*/claude-self-heal|*/claude-automount)",
    1,
)
sh.write_text(st2, encoding="utf-8", newline="\n")
print("git-mode.sh patched")

# deploy-mount-fix install self-heal
dm = Path(r"D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-mount-fix.sh")
if dm.exists():
    dt = dm.read_text(encoding="utf-8")
    if "claude-self-heal" not in dt:
        dt = dt.replace(
            'install -m 755 "$AUTO_SRC" /usr/local/bin/claude-automount\nok "claude-automount -> /usr/local/bin/"',
            'install -m 755 "$AUTO_SRC" /usr/local/bin/claude-automount\nok "claude-automount -> /usr/local/bin/"\n'
            'if [ -f "$SERVER_DIR/claude-self-heal.sh" ]; then\n'
            '  install -m 755 "$SERVER_DIR/claude-self-heal.sh" /usr/local/bin/claude-self-heal\n'
            '  sed -i \'s/\\r$//\' /usr/local/bin/claude-self-heal 2>/dev/null || true\n'
            '  ok "claude-self-heal -> /usr/local/bin/"\n'
            'fi',
            1,
        )
        dm.write_text(dt, encoding="utf-8", newline="\n")
        print("deploy-mount-fix patched")
    else:
        print("deploy-mount-fix already has heal")

# add-user install self-heal next to automount
au = Path(r"D:\Smart\Claude-Code-Server\scripts\server\commands\add-user.sh")
if au.exists():
    at = au.read_text(encoding="utf-8")
    if "claude-self-heal" not in at:
        needle = '''if [ -x /usr/local/bin/claude-automount ]; then
    install -m 755 /usr/local/bin/claude-automount "/home/$USERNAME/.local/bin/claude-automount"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-automount"
    ok "~/.local/bin/claude-automount installed"
fi
'''
        add = needle + '''if [ -x /usr/local/bin/claude-self-heal ]; then
    install -m 755 /usr/local/bin/claude-self-heal "/home/$USERNAME/.local/bin/claude-self-heal"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-self-heal"
    ok "~/.local/bin/claude-self-heal installed"
fi
'''
        if needle in at:
            at = at.replace(needle, add, 1)
            au.write_text(at, encoding="utf-8", newline="\n")
            print("add-user patched")
        else:
            print("add-user needle missing, skip")
    else:
        print("add-user already has heal")

print("ALL_PATCH_OK")
