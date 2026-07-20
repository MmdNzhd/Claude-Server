from pathlib import Path
root = Path(__file__).resolve().parents[2]

gm = root / "scripts/client/git-mode.sh"
g = gm.read_text(encoding="utf-8")

# Clearer final failure message
old = '''    warn "Laptop SSH still not accepting the server key."
    warn "System Settings -> General -> Sharing -> Remote Login: ON, allow '${user}'."
    unset LAPTOP_ADMIN_PW
    return 1
}'''
new = '''    warn "Laptop SSH still not accepting the server key."
    warn "Mac login user is '${user}' (whoami) — NOT the server username."
    warn "Server username stays '${REMOTE_USER:-mohammad}'. Reverse SSH must allow Mac user '${user}'."
    warn "System Settings -> General -> Sharing -> Remote Login: ON, allow '${user}' (or All users)."
    unset LAPTOP_ADMIN_PW
    return 1
}'''
if old not in g:
    raise SystemExit('gm fail msg missing')
g = g.replace(old, new, 1)

# Don't re-prompt password on second pass if already asked once this session
old_read = '''read_laptop_admin_password() {
    [ -n "${LAPTOP_ADMIN_PW:-}" ] && return 0
    printf '    \\033[0;33mMac password (one time, 45s timeout, fixes Remote Login):\\033[0m\\n' >/dev/tty 2>/dev/null || true
    # -t prevents infinite hang when no TTY / user walks away
    if ! read -rs -t 45 LAPTOP_ADMIN_PW </dev/tty 2>/dev/null; then
        read -rs -t 45 LAPTOP_ADMIN_PW 2>/dev/null || LAPTOP_ADMIN_PW=""
    fi
    echo '' >/dev/tty 2>/dev/null || echo ''
    [ -n "${LAPTOP_ADMIN_PW:-}" ]
}'''
new_read = '''read_laptop_admin_password() {
    [ -n "${LAPTOP_ADMIN_PW:-}" ] && return 0
    # Only one interactive prompt per connect (avoid double-ask on retry pass).
    if [ "${_MAC_ADMIN_PW_ASKED:-0}" -eq 1 ]; then
        return 1
    fi
    _MAC_ADMIN_PW_ASKED=1
    printf '    \\033[0;33mMac password (one time, 45s timeout, fixes Remote Login):\\033[0m\\n' >/dev/tty 2>/dev/null || true
    if ! read -rs -t 45 LAPTOP_ADMIN_PW </dev/tty 2>/dev/null; then
        read -rs -t 45 LAPTOP_ADMIN_PW 2>/dev/null || LAPTOP_ADMIN_PW=""
    fi
    echo '' >/dev/tty 2>/dev/null || echo ''
    [ -n "${LAPTOP_ADMIN_PW:-}" ]
}'''
if old_read not in g:
    raise SystemExit('read_pw missing')
g = g.replace(old_read, new_read, 1)

# Fixing Mac SSH access message clarify
g = g.replace(
    '''warn "Fixing Mac SSH access for '${user}' (password once)..."''',
    '''warn "Fixing Mac SSH access for Mac user '${user}' (server user is '${REMOTE_USER:-?}'; password once)..."''',
    1,
)
gm.write_text(g, encoding="utf-8", newline="\n")

cs = root / "scripts/client/mac/connect.sh"
c = cs.read_text(encoding="utf-8")
c = c.replace(
    '''    warn "Mac: System Settings -> General -> Sharing -> Remote Login = ON"
    warn "     Allow access for user: ${LAPTOP_USER:-$(whoami)}  (or All users)"''',
    '''    warn "Mac Sharing must allow Mac login '${LAPTOP_USER:-$(whoami)}' (whoami) — not server user '${REMOTE_USER}'."
    warn "System Settings -> General -> Sharing -> Remote Login = ON, allow '${LAPTOP_USER:-$(whoami)}' (or All users)"''',
    1,
)
cs.write_text(c, encoding="utf-8", newline="\n")

for rel in [
    "scripts/client/mac/connect.sh",
    "scripts/client/windows/connect.ps1",
    "scripts/client/mac/connect-version.txt",
    "scripts/client/windows/connect-version.txt",
]:
    p = root / rel
    t = p.read_text(encoding="utf-8").replace("20260717.16", "20260717.17")
    if "20260717.17" not in t:
        raise SystemExit(rel)
    p.write_text(t, encoding="utf-8", newline="\n")

print("ok")
