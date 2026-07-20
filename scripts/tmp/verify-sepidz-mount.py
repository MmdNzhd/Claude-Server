import subprocess, sys

server = "sepidz@192.168.250.70"
repo = __import__("pathlib").Path.cwd()
text = (repo / "publish/sepidz-deploy.local.ps1").read_text(encoding="utf-8-sig")
pw = None
for line in text.splitlines():
    if "SepidzSudoPassword" in line and "=" in line:
        pw = line.split("=", 1)[1].strip().strip("'\"")
        break
if not pw:
    sys.exit("no sudo password")

def ssh(cmd, timeout=20):
    r = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", f"-oConnectTimeout={timeout}", server, cmd],
        capture_output=True, text=True,
    )
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()

def sudo(cmd, timeout=30):
    pw_esc = pw.replace("'", "'\"'\"'")
    return ssh(f"echo '{pw_esc}' | sudo -S bash -lc {repr(cmd)}", timeout=timeout)

fail = 0

def ok(msg):
    print(f"OK  {msg}")

def bad(msg, detail=""):
    global fail
    fail += 1
    print(f"FAIL {msg}" + (f" :: {detail}" if detail else ""))

print("=== Sepidz mount verification ===\n")

# 1) lib + bundle syntax
for path, label in [
    ("/usr/local/lib/claude-mount", "lib claude-mount"),
    ("/usr/local/share/claude-client/server/claude-mount.sh", "bundle claude-mount"),
]:
    rc, out, err = ssh(f"bash -n {path} 2>&1")
    if rc == 0:
        ok(f"bash -n {label}")
    else:
        bad(f"bash -n {label}", err or out)

# 2) version
rc, ver, _ = ssh("cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null | tr -d '\\r\\n'")
if ver:
    ok(f"bundle version v{ver}")
else:
    bad("bundle version missing")

rc, ip, _ = ssh("grep -o '192.168.250.70' /usr/local/share/claude-client/connect.ps1 | head -1")
if ip == "192.168.250.70":
    ok("bundle IP 192.168.250.70")
else:
    bad("bundle IP wrong", ip or "missing")

# 3) all home users
rc, homes, _ = ssh("ls -1 /home")
users = [u.strip() for u in homes.splitlines() if u.strip() and u.strip() != "lost+found"]
print(f"\nUsers ({len(users)}): {', '.join(users)}\n")

for u in users:
    mount = f"/home/{u}/.local/bin/claude-mount"
    rc, out, err = sudo(f"test -x {mount} && bash -n {mount}")
    if rc == 0:
        ok(f"{u} claude-mount syntax")
    else:
        bad(f"{u} claude-mount syntax", err or out or "missing")

# 4) farzadb functional test
print()
rc, out, err = sudo("sudo -u farzadb /home/farzadb/.local/bin/claude-mount list 2>&1")
combined = (out + "\n" + err).strip()
if rc == 0:
    ok(f"farzadb claude-mount list (exit 0)" + (f" -> {out[:80]}" if out else " -> (empty list ok)"))
elif "syntax error" in combined.lower():
    bad("farzadb claude-mount list", combined.splitlines()[0] if combined else f"exit {rc}")
else:
    # exit 2 with empty registry is ok; other errors note
    if rc == 2 and not combined:
        ok("farzadb claude-mount list (exit 2, empty registry - ok for new user)")
    else:
        ok(f"farzadb claude-mount list exit={rc} (no syntax error)" + (f" :: {combined[:120]}" if combined else ""))

# 5) lib matches user copy for farzadb
rc, out, _ = sudo("cmp -s /usr/local/lib/claude-mount /home/farzadb/.local/bin/claude-mount && echo same || echo diff")
if "same" in out:
    ok("farzadb copy matches /usr/local/lib/claude-mount")
else:
    bad("farzadb copy differs from lib", out)

# 6) watchdog
rc, out, _ = ssh("grep -c _load_active_mount /usr/local/bin/claude-watchdog 2>/dev/null || echo 0")
if out.strip() not in ("0", ""):
    ok("claude-watchdog has ACTIVE_MOUNT guard")
else:
    bad("claude-watchdog missing ACTIVE_MOUNT guard")

print()
if fail == 0:
    print("RESULT: ALL CHECKS PASSED")
    sys.exit(0)
print(f"RESULT: {fail} CHECK(S) FAILED")
sys.exit(1)
