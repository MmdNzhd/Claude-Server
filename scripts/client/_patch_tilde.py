from pathlib import Path

root = Path(__file__).resolve().parents[2]
gm = root / "scripts/client/git-mode.sh"
text = gm.read_text(encoding="utf-8")

old_push = '''push_remote_file_if_changed() {
    local src="$1" remote="$2" local_h="" remote_h=""
    [ -f "$src" ] || return 0
    local_h="$(local_file_sha256 "$src" 2>/dev/null || true)"
    remote_h="$(sshx "sha256sum '$remote' 2>/dev/null | awk '{print \\$1}'" 2>/dev/null | tr -d '\\r\\n')"
    [ -n "$local_h" ] && [ "$local_h" = "$remote_h" ] && return 0
    sshx "mkdir -p \\"\\$(dirname '$remote')\\"" 2>/dev/null || true
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:$remote" 2>/dev/null || return 1
    case "$remote" in
        */laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh)
            sshx "chmod +x '$remote'" 2>/dev/null || true ;;
    esac
}'''

# Read exact content from file between markers
lines = text.splitlines(keepends=True)
start = next(i for i, l in enumerate(lines) if l.startswith("push_remote_file_if_changed()"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("push_laptop_exec_bundle()"))
new_push = '''push_remote_file_if_changed() {
    # remote may be ~/path — never chmod/sha256 with quoted "~" (no expand).
    # scp still gets the ~/ form (OpenSSH expands after host:).
    local src="$1" remote="$2" local_h="" remote_h="" rpath
    [ -f "$src" ] || return 0
    case "$remote" in
        \'~\'/*) rpath="\\$HOME/${remote#\\~/}" ;;
        \'~\')   rpath=\'\\$HOME\' ;;
        *)     rpath="$remote" ;;
    esac
    local_h="$(local_file_sha256 "$src" 2>/dev/null || true)"
    remote_h="$(sshx "sha256sum $rpath 2>/dev/null | awk \'{print \\$1}\'" 2>/dev/null | tr -d \'\\r\\n\')"
    [ -n "$local_h" ] && [ "$local_h" = "$remote_h" ] && return 0
    sshx "mkdir -p \\"\\$(dirname $rpath)\\"" >/dev/null 2>&1 || true
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:$remote" 2>/dev/null || return 1
    case "$remote" in
        */laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh)
            sshx "chmod +x $rpath" >/dev/null 2>&1 || true ;;
    esac
    return 0
}

'''
# Fix the case pattern - I over-escaped. Write cleanly:
new_push = r'''push_remote_file_if_changed() {
    # remote may be ~/path — never run remote cmds with quoted "~" (no expand).
    # scp still gets the ~/ form (OpenSSH expands after host:).
    local src="$1" remote="$2" local_h="" remote_h="" rpath
    [ -f "$src" ] || return 0
    case "$remote" in
        '~/'*) rpath="\$HOME/${remote#~/}" ;;
        '~')   rpath='\$HOME' ;;
        *)     rpath="$remote" ;;
    esac
    local_h="$(local_file_sha256 "$src" 2>/dev/null || true)"
    remote_h="$(sshx "sha256sum $rpath 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')"
    [ -n "$local_h" ] && [ "$local_h" = "$remote_h" ] && return 0
    sshx "mkdir -p \"\$(dirname $rpath)\"" >/dev/null 2>&1 || true
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:$remote" 2>/dev/null || return 1
    case "$remote" in
        */laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh)
            sshx "chmod +x $rpath" >/dev/null 2>&1 || true ;;
    esac
    return 0
}

'''

text2 = "".join(lines[:start]) + new_push + "".join(lines[end:])

# Fix push_laptop_exec_bundle setup invocation + silence
old_setup = "sshx '~/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>/dev/null || true"
new_setup = "sshx '\$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' >/dev/null 2>&1 || true"
# In a Python raw replace on file content, we want the shell source to contain $HOME not \$HOME
# When we write to file: sshx '$HOME/.local/bin/...' 
new_setup = "sshx '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' >/dev/null 2>&1 || true"
if old_setup not in text2:
    raise SystemExit("setup line missing")
text2 = text2.replace(old_setup, new_setup, 1)

# Fix Mac-local ~ expansion in _chmod (double-quoted ~ becomes /Users/... on Mac)
old_chmod1 = '[ -n "$src" ] && _chmod="chmod +x ~/.local/bin/claude-mount; grep -q \'CLAUDE_LOCAL_BIN_PATH\' ~/.bashrc || printf \'\\n# CLAUDE_LOCAL_BIN_PATH\\nexport PATH=\\$HOME/.local/bin:\\$PATH\\n\' >> ~/.bashrc"'
# read exact from file
import re
m = re.search(r'\[ -n "\$src" \] && _chmod="chmod \+x ~/.local/bin/claude-mount;.*?\n', text2)
if not m:
    # try find line
    for i,l in enumerate(text2.splitlines()):
        if '_chmod="chmod +x ~/.local/bin/claude-mount' in l:
            print("FOUND chmod line", i+1, l[:120])
            break
    else:
        raise SystemExit("chmod line not found")

lines2 = text2.splitlines(keepends=True)
for i, l in enumerate(lines2):
    if '_chmod="chmod +x ~/.local/bin/claude-mount' in l:
        lines2[i] = '        [ -n "$src" ] && _chmod="chmod +x \\$HOME/.local/bin/claude-mount; grep -q \'CLAUDE_LOCAL_BIN_PATH\' \\$HOME/.bashrc || printf \'\\n# CLAUDE_LOCAL_BIN_PATH\\nexport PATH=\\$HOME/.local/bin:\\$PATH\\n\' >> \\$HOME/.bashrc"\n'
    if '_chmod="${_chmod:+"$_chmod; "}chmod +x ~/.local/bin/claude-git-setup"' in l or "chmod +x ~/.local/bin/claude-git-setup" in l:
        lines2[i] = '        [ -n "$git_src" ] && _chmod="${_chmod:+"$_chmod; "}chmod +x \\$HOME/.local/bin/claude-git-setup"\n'

text2 = "".join(lines2)
gm.write_text(text2, encoding="utf-8", newline="\n")
print("patched push + chmod")

# bump version 13 -> 14
for rel in [
    "scripts/client/mac/connect.sh",
    "scripts/client/windows/connect.ps1",
    "scripts/client/mac/connect-version.txt",
    "scripts/client/windows/connect-version.txt",
]:
    p = root / rel
    t = p.read_text(encoding="utf-8")
    t2 = t.replace("20260717.13", "20260717.14")
    if t == t2:
        raise SystemExit(f"version not 13 in {rel}")
    p.write_text(t2, encoding="utf-8", newline="\n")
    print("ver", rel)

# test assert
test = root / "scripts/client/tests/test-git-mode-deep.ps1"
tt = test.read_text(encoding="utf-8")
needle = "Assert ($gitModeSh -match 'password at most once') 'git-mode.sh Mac admin password once'"
extra = needle + "\nAssert ($gitModeSh -match 'never run remote cmds with quoted') 'git-mode.sh documents tilde chmod fix'"
if "never run remote cmds with quoted" not in tt:
    if needle not in tt:
        # softer: just add near push_remote
        pass
    else:
        test.write_text(tt.replace(needle, extra, 1), encoding="utf-8", newline="\n")
        print("test ok")
print("done")
