#!/usr/bin/env python3
"""Exhaustive failure-class inventory from smart connect day log (deduped)."""
from __future__ import annotations
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

LOG = Path("/home/smart/.claude/logs/connect-20260719.log")
TS = re.compile(r"^\[(20\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\] \[(\w+)\] \[([^\]]+)\] (.*)$")

CLASSES = [
    ("ORPHAN_KILL", r"ORPHAN_TUNNEL: killing"),
    ("ENSURE_KILL_ORPHAN", r"ENSURE_TUNNEL killing orphan"),
    ("ENSURE_KILL_STALE_BG", r"ENSURE_TUNNEL killing stale bg"),
    ("ENSURE_SPAWN", r"ENSURE_TUNNEL spawned"),
    ("ENSURE_OK", r"ENSURE_TUNNEL ok=1"),
    ("ENSURE_FAIL", r"ENSURE_TUNNEL ok=0"),
    ("STALE_FORWARD", r"STALE_FORWARD"),
    ("TUNNEL_DROP", r"TUNNEL_DROP"),
    ("TUNNEL_DOWN", r"TUNNEL_SYNC ok=0 reason=tunnel_down"),
    ("SOFT_FAIL", r"TUNNEL_SYNC soft_fail"),
    ("CONN_DROP", r"connection dropped"),
    ("RECOVERY", r"RECOVERY_BEGIN"),
    ("CLEAR_MOUNT", r"CLEAR_MOUNT project="),
    ("UNMOUNT", r"unmounted:"),
    ("REFUSED", r"Connection refused"),
    ("BANNER_MISS", r"TUNNEL_BANNER miss="),
    ("MAXSTARTUPS", r"MaxStartups|maxstartups"),
    ("PUSH_CONF", r"PUSH_CONF"),
    ("SELF_HEAL", r"self-heal|self_heal|claude-self-heal"),
    ("SYNTAX_ERR", r"syntax error|unexpected EOF|elif"),
    ("AUTH_FORCE", r"cursor-auth-sync --force"),
    ("RELAUNCH", r"cursor not on target|relaunching"),
    ("EIO", r"\bEIO\b|Input/output error"),
    ("MOUNT_FAIL", r"STEP end: Mounting.*fail|MOUNT_UP.*fail|mount failed"),
    ("FALSE_LEAK", r"\bFalse\b"),
    ("LOG_SYNC", r"Sync-ConnectLog|log sync|CONNECT_LOG_SYNC|flush"),
    ("ELEVATED", r"elevated=True|elevated=yes"),
    ("WRONG_PKG", r"claude-code-client"),
    ("VERSION", r"CONNECT_VERSION=|session start v"),
    ("SESSION_END", r"session end"),
    ("SSH_TIMEOUT", r"exit=124|wait_timeout"),
    ("PERF_FLOOD", r"PERF\[cim_query\]"),
    ("TRACE_SYNC", r"TUNNEL_SYNC: bg_alive"),
]

def main():
    raw = LOG.read_text(errors="replace").splitlines()
    seen=set(); uniq=[]
    for line in raw:
        if line in seen: continue
        seen.add(line)
        m=TS.match(line)
        if not m: continue
        uniq.append({
            "ts": datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f"),
            "level": m.group(2), "sid": m.group(3), "msg": m.group(4), "line": line
        })
    print(f"DEDUPED={len(uniq)} RAW={len(raw)} DUP_FRAC={1-len(uniq)/max(1,len(raw)):.3f}")

    counts=Counter(); samples=defaultdict(list)
    for e in uniq:
        for name,pat in CLASSES:
            if re.search(pat, e["msg"], re.I):
                counts[name]+=1
                if len(samples[name])<3:
                    samples[name].append(e["line"][:180])

    print("\n=== CLASS COUNTS (deduped day log smart) ===")
    for name,_ in CLASSES:
        print(f"  {counts[name]:5d}  {name}")

    print("\n=== SAMPLES ===")
    for name,_ in CLASSES:
        if counts[name]==0: continue
        print(f"\n## {name} ({counts[name]})")
        for s in samples[name]:
            print(" ", s)

    # WARN/ERROR unique messages
    print("\n=== UNIQUE WARN/ERROR (top) ===")
    w=Counter()
    for e in uniq:
        if e["level"] in ("WARN","ERROR"):
            # normalize pids
            msg=re.sub(r"pid=\d+","pid=N", e["msg"])
            msg=re.sub(r"ms=\d+","ms=N", msg)
            msg=re.sub(r"gen=\d+","gen=N", msg)
            w[msg]+=1
    for msg,c in w.most_common(40):
        print(f"  {c:4d}  [{msg[:150]}]")

    # timeline of destructive ops only
    print("\n=== DESTRUCTIVE TIMELINE ===")
    for e in uniq:
        if any(re.search(p, e["msg"], re.I) for _,p in [
            ("", r"ORPHAN_TUNNEL: killing|ENSURE_TUNNEL killing|TUNNEL_STOP|CLEAR_MOUNT project|unmounted:|connection dropped|RECOVERY_BEGIN|ENSURE_TUNNEL spawned|STALE_FORWARD: clearing")
        ]):
            print(f"{e['ts']} | {e['msg'][:140]}")

if __name__ == "__main__":
    main()
