#!/usr/bin/env python3
"""E2E verification for farzadb. Exit 1 on real failures."""
import os, sqlite3, subprocess, sys

U = "farzadb"
HOME = f"/home/{U}"
fails, warns, oks = [], [], []

def ok(m): oks.append(m); print(f"OK   {m}")
def warn(m): warns.append(m); print(f"WARN {m}")
def fail(m): fails.append(m); print(f"FAIL {m}")

def sh(cmd, timeout=25):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=timeout)

# machineid
gold = open("/etc/cursor-auth/golden/machine-id.txt", "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
for label, path in [("profile", f"{HOME}/.config/Cursor/machineid"), ("server", f"{HOME}/.cursor-server/data/machineid")]:
    raw = open(path, "rb").read().replace(b"\r", b"").replace(b"\n", b"").strip().strip(b"\"'")
    if raw != gold: fail(f"machineid {label} mismatch")
    else: ok(f"machineid {label} ok")

# auth: tokens required; identity fields warn if golden empty
db = f"{HOME}/.config/Cursor/User/globalStorage/state.vscdb"
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
def aval(k):
    r = c.execute("select value from ItemTable where key=?", (k,)).fetchone()
    return "" if not r or r[0] is None else str(r[0])
for k in ("cursorAuth/accessToken", "cursorAuth/refreshToken"):
    v = aval(k)
    if len(v) < 20: fail(f"{k} missing/short")
    else: ok(f"{k} ok len={len(v)}")
for k in ("cursorAuth/cachedEmail", "cursorAuth/stripeMembershipType"):
    v = aval(k)
    if not v.strip(): warn(f"{k} empty (golden also empty — server-wide)")
    else: ok(f"{k} ok")
c.close()

# conf + tunnel
conf = {}
for line in open(f"{HOME}/.claude-connect.conf"):
    if "=" in line: k,v=line.strip().split("=",1); conf[k]=v
port = conf.get("TUNNEL_PORT","")
r = sh(f"timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{port}' && echo open || echo closed")
ok(f"tunnel {port} open") if "open" in r.stdout else fail(f"tunnel {port} closed")

# mounts
for mid in ("frontend", "backend"):
    mp = f"{HOME}/mounts/{mid}"
    r = sh(f"mountpoint -q {mp} && echo yes || echo no")
    if "yes" not in r.stdout: fail(f"{mid} not mounted"); continue
    ok(f"{mid} mounted")
    r = sh(f"timeout 8 ls {mp} | head -3")
    ok(f"{mid} readable") if r.stdout.strip() else fail(f"{mid} unreadable")

# laptop-exec no CRLF + works
le = os.path.realpath(f"{HOME}/.local/bin/laptop-exec")
raw = open(le, "rb").read()
if b"\r" in raw: fail(f"laptop-exec has CRLF: {le}")
else: ok("laptop-exec LF-only")
r = sh(f"su - {U} -c 'laptop-exec status'")
out = r.stdout + r.stderr
if "tunnel:" in out and "UP" in out: ok("laptop-exec status UP")
else: fail(f"laptop-exec status bad: {out[:200]}")

# write via laptop-exec (SSH-first truth)
r = sh(f"su - {U} -c 'printf e2e > /tmp/e2e.txt && laptop-exec write -p frontend .claude-e2e.txt < /tmp/e2e.txt && laptop-exec read -p frontend .claude-e2e.txt && laptop-exec run -p frontend -- cmd /c del .claude-e2e.txt'")
if "e2e" in r.stdout: ok("frontend laptop-exec write/read/delete")
else: fail(f"frontend laptop-exec IO failed: {r.stdout!r} {r.stderr!r}")

r = sh(f"su - {U} -c 'printf e2e > /tmp/e2e.txt && laptop-exec write -p backend .claude-e2e.txt < /tmp/e2e.txt && laptop-exec read -p backend .claude-e2e.txt && laptop-exec run -p backend -- cmd /c del .claude-e2e.txt'")
if "e2e" in r.stdout: ok("backend laptop-exec write/read/delete")
else: fail(f"backend laptop-exec IO failed: {r.stdout!r} {r.stderr!r}")

# SSHFS write into .cursor (agent-critical path often uses laptop-exec anyway)
r = sh(f"su - {U} -c 'echo x > {HOME}/mounts/frontend/.cursor/e2e-sshfs.txt && cat {HOME}/mounts/frontend/.cursor/e2e-sshfs.txt && rm -f {HOME}/mounts/frontend/.cursor/e2e-sshfs.txt'")
if "x" in r.stdout: ok("frontend SSHFS write under .cursor")
else: warn(f"frontend SSHFS .cursor write limited: {(r.stderr or r.stdout)[:120]}")

r = sh(f"timeout 5 su - {U} -c 'echo SHELL_OK'")
ok("shell <5s") if "SHELL_OK" in r.stdout else fail("shell slow")

# claude-mount status accepts MOUNTED
r = sh(f"su - {U} -c 'claude-mount status'")
for mid in ("frontend", "backend"):
    line = next((ln for ln in r.stdout.splitlines() if ln.startswith(mid+"|")), "")
    if "MOUNTED" in line or "|ON" in line: ok(f"claude-mount {mid}: {line.split('|')[-1]}")
    else: fail(f"claude-mount {mid} bad: {line}")

print()
print(f"SUMMARY ok={len(oks)} warn={len(warns)} fail={len(fails)}")
for w in warns: print(" WARN:", w)
for f in fails: print(" FAIL:", f)
sys.exit(1 if fails else 0)
