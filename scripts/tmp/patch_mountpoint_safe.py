from pathlib import Path
import re

root = Path(r"D:\Smart\Claude-Code-Server")

# ---- laptop-exec-setup.sh ----
setup = root / "scripts/server/laptop-exec-setup.sh"
c = setup.read_text(encoding="utf-8")
old = '''        if [ "$require_mount" = "1" ]; then
            mountpoint -q "$d" 2>/dev/null || continue
        fi'''
new = '''        if [ "$require_mount" = "1" ]; then
            # Never use mountpoint -q: frozen SSHFS can hang. /proc/mounts is instant.
            mp="${d%/}"
            grep -F " $mp " /proc/mounts >/dev/null 2>&1 || continue
        fi'''
if "Never use mountpoint -q: frozen SSHFS" in c:
    print("SKIP setup mountpoint")
elif old in c:
    setup.write_text(c.replace(old, new), encoding="utf-8", newline="\n")
    print("OK setup mountpoint -> /proc/mounts")
else:
    raise SystemExit("setup pattern missing")

# ---- laptop-exec.sh ----
le = root / "scripts/server/laptop-exec.sh"
c = le.read_text(encoding="utf-8")
old = '''    if ! timeout 1 stat "$mp" >/dev/null 2>&1; then echo "NOT_MOUNTED"; return; fi
    if ! mountpoint -q "$mp" 2>/dev/null; then echo "NOT_MOUNTED"; return; fi'''
new = '''    if ! timeout 1 stat "$mp" >/dev/null 2>&1; then echo "NOT_MOUNTED"; return; fi
    # Prefer /proc/mounts over mountpoint -q (hangs on frozen SSHFS).
    if ! grep -F " $mp " /proc/mounts >/dev/null 2>&1; then echo "NOT_MOUNTED"; return; fi'''
if "Prefer /proc/mounts over mountpoint" in c:
    print("SKIP laptop-exec mountpoint")
elif old in c:
    le.write_text(c.replace(old, new), encoding="utf-8", newline="\n")
    print("OK laptop-exec mountpoint -> /proc/mounts")
else:
    raise SystemExit("laptop-exec pattern missing")

# ---- claude-mount.sh ----
cm = root / "scripts/server/claude-mount.sh"
c = cm.read_text(encoding="utf-8")
if "_in_proc_mounts()" in c and "mountpoint -q" not in re.sub(r'#.*', '', c):
    print("SKIP claude-mount already safe")
else:
    # Insert helper before _is_mounted
    if "_in_proc_mounts()" not in c:
        marker = "_is_mounted() {"
        helper = '''_in_proc_mounts() {
    local mp="${1%/}"
    [ -n "$mp" ] || return 1
    # Instant; never hangs on frozen SSHFS (unlike mountpoint -q).
    grep -F " $mp " /proc/mounts >/dev/null 2>&1
}

_is_mounted() {'''
        if marker not in c:
            raise SystemExit("_is_mounted missing")
        c = c.replace(marker, helper, 1)
        # fix body of _is_mounted
        old_body = '''_is_mounted() {
    local lpath="$1"
    mountpoint -q "$lpath" 2>/dev/null && \\
        timeout 2 ls "$lpath" >/dev/null 2>&1
}'''
        # after insert, function starts with helper ending in _is_mounted() {
        old_body2 = '''_is_mounted() {
    local lpath="$1"
    mountpoint -q "$lpath" 2>/dev/null && \\
        timeout 2 ls "$lpath" >/dev/null 2>&1
}'''
        # The insert left duplicate _is_mounted opening - need careful replace of body only
        # Current state after replace: helper ends with "_is_mounted() {" then old body continues with "local lpath..."
        # Actually helper string ends with `_is_mounted() {` and original continues with `local lpath=...` and mountpoint.
        # So replace the mountpoint lines in _is_mounted body:
        c = c.replace(
            '''_is_mounted() {
    local lpath="$1"
    mountpoint -q "$lpath" 2>/dev/null && \\
        timeout 2 ls "$lpath" >/dev/null 2>&1
}''',
            '''_is_mounted() {
    local lpath="$1"
    _in_proc_mounts "$lpath" && \\
        timeout 2 ls "$lpath" >/dev/null 2>&1
}''',
            1,
        )
        # If insert already happened, body may still have mountpoint
        c = c.replace(
            '''    local lpath="$1"
    mountpoint -q "$lpath" 2>/dev/null && \\
        timeout 2 ls "$lpath" >/dev/null 2>&1
}''',
            '''    local lpath="$1"
    _in_proc_mounts "$lpath" && \\
        timeout 2 ls "$lpath" >/dev/null 2>&1
}''',
            1,
        )

    # Replace remaining mountpoint -q command uses (not comments about "mountpoint" word in error strings)
    replacements = [
        ('if ! mountpoint -q "$lpath" 2>/dev/null; then', 'if ! _in_proc_mounts "$lpath"; then'),
        ('if mountpoint -q "$lpath" 2>/dev/null && timeout 2 ls "$lpath" >/dev/null 2>&1; then', 'if _is_mounted "$lpath"; then'),
        ('if timeout 2 mountpoint -q "$lpath" 2>/dev/null; then', 'if _in_proc_mounts "$lpath"; then'),
        ('if mountpoint -q "$lpath" 2>/dev/null; then', 'if _in_proc_mounts "$lpath"; then'),
    ]
    for a, b in replacements:
        n = c.count(a)
        if n:
            c = c.replace(a, b)
            print(f"OK claude-mount replaced x{n}: {a[:40]}...")

    # Verify no bare mountpoint -q left as command
    left = []
    for i, line in enumerate(c.splitlines(), 1):
        s = line.strip()
        if s.startswith("#"):
            continue
        if "mountpoint -q" in line:
            left.append(f"{i}:{line.strip()}")
    if left:
        print("REMAINING mountpoint -q:")
        for x in left:
            print(" ", x)
        raise SystemExit("still has mountpoint -q")
    cm.write_text(c, encoding="utf-8", newline="\n")
    print("OK claude-mount mountpoint-safe")

print("PATCH_MP_DONE")
