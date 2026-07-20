"""Harden Mac connect: $HOME remote paths, password timeout, bump .15."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
gm = root / "scripts/client/git-mode.sh"
text = gm.read_text(encoding="utf-8")

# 1) In sshx "..." strings, replace bare ~/path with $HOME/path (escaped for local double quotes).
# Do NOT touch scp ...:$ALIAS:~/ or comments about scp tilde, or case '~/'*) patterns, or push remote='~/'.

def fix_sshx_tildes(content: str) -> str:
    lines = content.splitlines(keepends=True)
    out = []
    for line in lines:
        if "scp " in line and "$ALIAS:~/" in line:
            out.append(line)
            continue
        if "ALIAS:$remote" in line or 'ALIAS:$RemotePath' in line:
            out.append(line)
            continue
        if "never run remote" in line or "scp still gets" in line:
            out.append(line)
            continue
        if "case \"$remote\"" in line or "case \"$RemotePath\"" in line:
            out.append(line)
            continue
        # leave single-quoted remote path args to push_remote_file ('~/.local/...')
        if "push_remote_file_if_changed" in line and "'~/" in line:
            out.append(line)
            continue
        if "sshx" in line and "~/" in line and "\$HOME" not in line:
            # Replace ~/.xxx with \$HOME/.xxx inside the line (remote path)
            line2 = re.sub(r'(?<![/\$])~/(\.[\w./-]+)', r'\\$HOME/\1', line)
            # also bare ~/.claude without needing word
            if line2 != line:
                line = line2
        out.append(line)
    return "".join(out)

text = fix_sshx_tildes(text)

# 2) Password read with timeout (no infinite hang)
old_pw = '''read_laptop_admin_password() {
    [ -n "${LAPTOP_ADMIN_PW:-}" ] && return 0
    printf '    \\033[0;33mMac password (one time, fixes Remote Login):\\033[0m\\n' >/dev/tty 2>/dev/null || true
    read -rs LAPTOP_ADMIN_PW </dev/tty 2>/dev/null || read -rs LAPTOP_ADMIN_PW || true
    echo '' >/dev/tty 2>/dev/null || echo ''
    [ -n "${LAPTOP_ADMIN_PW:-}" ]
}'''

# Find and replace by markers
lines = text.splitlines(keepends=True)
start = next(i for i, l in enumerate(lines) if l.startswith("read_laptop_admin_password()"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("run_mac_admin_cmd()"))
new_pw = '''read_laptop_admin_password() {
    [ -n "${LAPTOP_ADMIN_PW:-}" ] && return 0
    printf '    \\033[0;33mMac password (one time, 45s timeout, fixes Remote Login):\\033[0m\\n' >/dev/tty 2>/dev/null || true
    # -t prevents infinite hang when no TTY / user walks away
    if ! read -rs -t 45 LAPTOP_ADMIN_PW </dev/tty 2>/dev/null; then
        read -rs -t 45 LAPTOP_ADMIN_PW 2>/dev/null || LAPTOP_ADMIN_PW=""
    fi
    echo '' >/dev/tty 2>/dev/null || echo ''
    [ -n "${LAPTOP_ADMIN_PW:-}" ]
}

'''
text = "".join(lines[:start]) + new_pw + "".join(lines[end:])

# 3) Silence noisy sshx in initialize mkdir (stdout leak into step)
text = text.replace(
    'sshx "mkdir -p \\$HOME/.local/bin" 2>/dev/null || true',
    'sshx "mkdir -p \\$HOME/.local/bin" >/dev/null 2>&1 || true',
)
# also if still unescaped form
text = text.replace(
    'sshx "mkdir -p ~/.local/bin" 2>/dev/null || true',
    'sshx "mkdir -p \\$HOME/.local/bin" >/dev/null 2>&1 || true',
)

gm.write_text(text, encoding="utf-8", newline="\n")
print("git-mode.sh hardened")

# 4) Fix deploy staging paths in REPO (already correct) - also add mac/ copies for safety
dcb = root / "scripts/server/commands/deploy-client-bundle.sh"
d = dcb.read_text(encoding="utf-8")
# Ensure staging uses scripts/client/connect-ui.sh (not mac/)
if "scripts/client/mac/connect-ui.sh" in d:
    d = d.replace("scripts/client/mac/connect-ui.sh", "scripts/client/connect-ui.sh")
    d = d.replace("scripts/client/mac/editor-launch.sh", "scripts/client/editor-launch.sh")
    print("fixed repo deploy staging paths")
# Fail deploy if mac UI missing (don't silently ship broken Mac bundle)
needle = 'ok "mac/$name"'
guard = '''    if [ ! -f "$src" ]; then
        if [ "$name" = "connect-ui.sh" ] || [ "$name" = "editor-launch.sh" ] || [ "$name" = "git-mode.sh" ]; then
            fail "required mac file missing: $name (src=$src)"
        fi
        warn "skip missing mac/$name"
        continue
    fi'''
# Replace the soft skip for mac_files loop - only if not already failing hard
old_skip = '''    if [ ! -f "$src" ]; then
        warn "skip missing mac/$name"
        continue
    fi'''
if old_skip in d and "required mac file missing" not in d:
    d = d.replace(old_skip, guard, 1)
    print("deploy fails hard if mac UI missing")
dcb.write_text(d, encoding="utf-8", newline="\n")

# 5) bump version
for rel in [
    "scripts/client/mac/connect.sh",
    "scripts/client/windows/connect.ps1",
    "scripts/client/mac/connect-version.txt",
    "scripts/client/windows/connect-version.txt",
]:
    p = root / rel
    t = p.read_text(encoding="utf-8")
    t2 = t.replace("20260717.14", "20260717.15").replace("20260717.13", "20260717.15")
    if "20260717.15" not in t2:
        raise SystemExit(f"bump failed {rel}")
    p.write_text(t2, encoding="utf-8", newline="\n")
    print("ver", rel)

# 6) test asserts
test = root / "scripts/client/tests/test-git-mode-deep.ps1"
tt = test.read_text(encoding="utf-8")
if "45s timeout" not in tt:
    needle = "Assert ($gitModeSh -match 'never run remote cmds with quoted') 'git-mode.sh documents tilde chmod fix'"
    if needle in tt:
        tt = tt.replace(
            needle,
            needle
            + "\nAssert ($gitModeSh -match '45s timeout') 'git-mode.sh Mac password has timeout'",
            1,
        )
        test.write_text(tt, encoding="utf-8", newline="\n")
        print("test updated")

print("done")
