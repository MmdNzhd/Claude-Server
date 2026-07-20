import re
from collections import Counter, defaultdict
from datetime import datetime

path = r"D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log"
with open(path, "r", encoding="utf-8", errors="replace") as f:
    lines = f.readlines()
print(f"lines={len(lines)} bytes_approx={sum(len(x) for x in lines)}")

ts_re = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\]")
# version / update
ver_keys = ("version", "UPDATE", "auto-update", "AutoUpdate", "bundle", "20260719", "20260717", "CLIENT", "connect-version")
# incident keys
inc_keys = (
    "CLEAR_MOUNT", "tunnel_down", "RECOVERY", "ENSURE", "ORPHAN", "soft_fail",
    "FINALLY_KEEP", "RECOVERY_SKIP", "EditorSeen", "Connection failed", "EIO",
    "SSHFS", "alreadyDown", "SESSION_LOOP", "SESSION_OPEN", "VERDICT",
    "MOUNT", "UNMOUNT", "spawn", "cursor", "LAUNCH", "AUTH", "error", "ERROR", "WARN"
)

def interesting(s, keys):
    low = s.lower()
    return any(k.lower() in low for k in keys)

print("\n=== VERSION / UPDATE LINES ===")
for i,l in enumerate(lines,1):
    if interesting(l, ver_keys) and any(x in l for x in ("2026", "version", "UPDATE", "Update", "bundle", "CLIENT")):
        if re.search(r"2026071[79]|connect-version|UPDATE|Auto-?Update|bundle_ver|client.version|version=", l, re.I):
            print(f"{i}:{l.rstrip()[:220]}")

print("\n=== SESSION TIMELINE (markers) ===")
markers = []
pat = re.compile(r"SESSION_LOOP begin|SESSION_OPEN|SESSION_CLOSE|CLEAR_MOUNT|tunnel_down|RECOVERY_|ENSURE_|ORPHAN|soft_fail|FINALLY_KEEP|RECOVERY_SKIP|EditorSeen|VERDICT_|LAUNCH_|MOUNT_|UNMOUNT|Connection failed|EIO|alreadyDown|ACTIVE_MOUNT|connect start|Connect starting|STEP begin|STEP end|auto.?update|Updated to|client version", re.I)
for i,l in enumerate(lines,1):
    if pat.search(l):
        markers.append((i,l.rstrip()))
print(f"marker_count={len(markers)}")
# show first 40 and last 80
show = markers[:40] + ([('...', '...')] if len(markers)>120 else []) + markers[-80:]
for item in show:
    if item[0]=='...':
        print("...")
        continue
    i,l = item
    print(f"{i}:{l[:240]}")

print("\n=== ERROR/WARN counts ===")
c = Counter()
err_lines = []
for i,l in enumerate(lines,1):
    if "[ERROR]" in l or " ERROR " in l:
        c["ERROR"] += 1
        err_lines.append((i,l.rstrip()))
    elif "[WARN]" in l or " WARN " in l:
        c["WARN"] += 1
print(dict(c))
print("--- last 40 ERROR ---")
for i,l in err_lines[-40:]:
    print(f"{i}:{l[:240]}")

print("\n=== LAST 60 LINES ===")
for i,l in enumerate(lines[-60:], len(lines)-59):
    print(f"{i}:{l.rstrip()[:240]}")

# time range
times=[]
for l in lines:
    m=ts_re.match(l)
    if m: times.append(m.group(1))
if times:
    print(f"\n=== TIME RANGE {times[0]} -> {times[-1]} ===")
