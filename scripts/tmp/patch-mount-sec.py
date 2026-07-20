from pathlib import Path

root = Path(r"D:\Smart\Claude-Code-Server")

# --- 1) claude-mount.sh: best-effort restore when TCP still open ---
p = root / "scripts/server/claude-mount.sh"
c = p.read_text(encoding="utf-8")
old = '''_restore_git() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    _git_tunnel_ready || return 0
    _restore_git_body "$rpath"
}'''
new = '''_restore_git() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ] || return 0
    # Prefer healthy tunnel; if probe fails but TCP still open (watchdog DOWN race),
    # still attempt restore. SSH ConnectTimeout=5 bounds hang; skip if TCP closed.
    if ! _git_tunnel_ready; then
        _tunnel_tcp_open || return 0
    fi
    _restore_git_body "$rpath"
}'''
if old not in c:
    if "_tunnel_tcp_open || return 0" in c and "_restore_git()" in c:
        print("SKIP mount _restore_git already patched")
    else:
        raise SystemExit("mount _restore_git pattern missing")
else:
    p.write_text(c.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("OK mount _restore_git best-effort TCP")

# --- 2) watchdog comment ---
w = root / "scripts/server/claude-watchdog.sh"
wc = w.read_text(encoding="utf-8")
wold = '''    if ! tunnel_up; then
        # Edge: tunnel down -> tear down every sshfs under mounts/ (incl. zombies)
        # Prefer claude-mount down so .git is restored from .git.server-session when possible.
        if [ -x "$MOUNT_BIN" ]; then
            "$MOUNT_BIN" down 2>/dev/null || true
        fi'''
wnew = '''    if ! tunnel_up; then
        # Edge: tunnel down -> tear down every sshfs under mounts/ (incl. zombies).
        # claude-mount down restores .git from .git.server-session when TCP still
        # briefly reachable (ConnectTimeout-bounded); otherwise recover on reconnect.
        if [ -x "$MOUNT_BIN" ]; then
            "$MOUNT_BIN" down 2>/dev/null || true
        fi'''
if wold not in wc:
    if "restores .git from .git.server-session when TCP" in wc:
        print("SKIP watchdog comment already patched")
    else:
        raise SystemExit("watchdog DOWN pattern missing")
else:
    w.write_text(wc.replace(wold, wnew, 1), encoding="utf-8", newline="\n")
    print("OK watchdog DOWN comment")

# --- 3) cursor-auth-refresh.sh ---
r = root / "scripts/server/cursor-auth-refresh.sh"
rc = r.read_text(encoding="utf-8")
n644 = rc.count("mode=0o644")
rc2 = rc.replace("mode=0o644", "mode=0o600")
rc2 = rc2.replace("os.chmod(mod.GOLDEN_DIR, 0o755)", "os.chmod(mod.GOLDEN_DIR, 0o700)")
if "mode=0o644" in rc2:
    raise SystemExit("refresh still has mode=0o644")
if "os.chmod(mod.GOLDEN_DIR, 0o755)" in rc2:
    raise SystemExit("refresh still chmod 755 golden")
if rc2 == rc and n644 == 0 and "0o700" in rc:
    print("SKIP refresh already 600/700")
else:
    r.write_text(rc2, encoding="utf-8", newline="\n")
    print(f"OK refresh golden 0600/0700 (replaced {n644} x 0o644)")

# --- 4) install.sh golden harden ---
inst = root / "scripts/server/commands/install.sh"
ic = inst.read_text(encoding="utf-8")
iold = '''mkdir -p /etc/cursor-auth/golden
chmod 700 /etc/cursor-auth/golden
# Secrets (auth.json etc.) written 0600 by cursor-auth-export; root cron + add-user sync.
ok "/etc/cursor-auth/golden ready (0700; secret files 0600)"'''
inew = '''mkdir -p /etc/cursor-auth/golden
chmod 700 /etc/cursor-auth/golden
# Harden any pre-existing secret files (legacy 644 from older installs/refresh).
chmod 600 /etc/cursor-auth/golden/* 2>/dev/null || true
# New secrets written 0600 by cursor-auth-export / refresh; root cron + add-user sync.
ok "/etc/cursor-auth/golden ready (0700; secret files 0600)"'''
if iold not in ic:
    if "chmod 600 /etc/cursor-auth/golden/*" in ic:
        print("SKIP install golden chmod already present")
    else:
        raise SystemExit("install golden block missing")
else:
    inst.write_text(ic.replace(iold, inew, 1), encoding="utf-8", newline="\n")
    print("OK install golden chmod 600 existing")

ic = inst.read_text(encoding="utf-8")
if "mkdir -p /etc/claude-code\nchmod 700 /etc/claude-code" in ic:
    print("SKIP install oauth dir already present")
else:
    marker = "if { [ -f /etc/claude-code/oauth.env ] && grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/claude-code/oauth.env 2>/dev/null; } \\"
    insert = (
        "# OAuth store: root-only dir + file (legacy /etc/environment stripped by deploy-auth/sync)\n"
        "mkdir -p /etc/claude-code\n"
        "chmod 700 /etc/claude-code\n"
        "if [ -f /etc/claude-code/oauth.env ]; then\n"
        "    chmod 600 /etc/claude-code/oauth.env\n"
        "fi\n"
        "\n"
    )
    if marker not in ic:
        print("WARN install oauth marker missing - skip oauth dir harden")
    else:
        inst.write_text(ic.replace(marker, insert + marker, 1), encoding="utf-8", newline="\n")
        print("OK install oauth.env dir harden")

# --- 5) test expectations ---
t = root / "scripts/server/test-cursor-auth-lib.py"
tc = t.read_text(encoding="utf-8")
told = '''        golden_mode = oct(os.stat(golden).st_mode & 0o777)
        if golden_mode != "0o755":
            print(f"WARN golden dir mode {golden_mode} (expected 755)")

        auth_mode = oct(os.stat(lib.AUTH_JSON).st_mode & 0o777)
        if auth_mode != "0o644":
            print(f"WARN auth.json mode {auth_mode} (expected 644)")'''
tnew = '''        golden_mode = oct(os.stat(golden).st_mode & 0o777)
        if golden_mode != "0o700":
            print(f"FAIL golden dir mode {golden_mode} (expected 700)")
            errors += 1

        auth_mode = oct(os.stat(lib.AUTH_JSON).st_mode & 0o777)
        if auth_mode != "0o600":
            print(f"FAIL auth.json mode {auth_mode} (expected 600)")
            errors += 1'''
if told not in tc:
    if 'expected 700' in tc:
        print("SKIP test already expects 700/600")
    else:
        raise SystemExit("test mode expectation pattern missing")
else:
    t.write_text(tc.replace(told, tnew, 1), encoding="utf-8", newline="\n")
    print("OK test expects golden 700/600")

print("PATCH_MOUNT_SEC_DONE")
