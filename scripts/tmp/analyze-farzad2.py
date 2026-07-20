import re, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
path = r"D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log"
lines = open(path, encoding='utf-8', errors='replace').readlines()

print("=== LAST 120 LINES ===")
for i,l in enumerate(lines[-120:], len(lines)-119):
    print(f"{i}:{l.rstrip()[:260]}")

print("\n=== ALL session start / UPDATE lines ===")
for i,l in enumerate(lines,1):
    if "session start v" in l or "UPDATE:" in l or "CONNECT_VERSION=" in l and "REMOTE_USER=farzadb" in l:
        if "session start" in l or l.strip().endswith("CONNECT_VERSION="+l.split("CONNECT_VERSION=")[-1][:20]) or "UPDATE:" in l:
            if "session start" in l or "UPDATE:" in l:
                print(f"{i}:{l.rstrip()[:220]}")

print("\n=== CLEAR_MOUNT / recovery / tunnel_down / soft_fail / RECOVERY_SKIP ===")
for i,l in enumerate(lines,1):
    if any(k in l for k in ("CLEAR_MOUNT","tunnel_down","soft_fail","RECOVERY_SKIP","FINALLY_KEEP","EditorSeen","already_down","recovery_gen","AUTO_RECOVERY","RECOVERY:")):
        print(f"{i}:{l.rstrip()[:260]}")

print("\n=== bash syntax error count ===")
n=sum(1 for l in lines if "syntax error near unexpected token" in l)
print("syntax_errors=", n)

print("\n=== WARN unique samples (top) ===")
from collections import Counter
w=Counter()
for l in lines:
    if "[WARN]" in l:
        # normalize
        s=re.sub(r"\[[0-9a-f]{12}\]","[sid]", l)
        s=re.sub(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+","TS", s)
        s=re.sub(r"pid=\d+","pid=N", s)
        s=re.sub(r"ms=\d+","ms=N", s)
        w[s.strip()[:160]] += 1
for s,c in w.most_common(15):
    print(f"{c}x {s}")
