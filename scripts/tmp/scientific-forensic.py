#!/usr/bin/env python3
"""Scientific forensic of connect log: dedupe, state machine, timing, hypothesis tests."""
from __future__ import annotations
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

LOG = Path("/home/smart/.claude/logs/connect-20260719.log")
TS_RE = re.compile(r"^\[(20\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\] \[(\w+)\] \[([^\]]+)\] (.*)$")

def parse(path: Path):
    raw = path.read_text(errors="replace").splitlines()
    events = []
    for i, line in enumerate(raw):
        m = TS_RE.match(line)
        if not m:
            continue
        ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f")
        events.append({
            "i": i, "ts": ts, "level": m.group(2), "sid": m.group(3),
            "msg": m.group(4), "line": line,
        })
    return events

def dedupe_exact(events):
    """Collapse exact duplicate consecutive/non-consecutive identical (ts,msg) lines.
    Log sync can append the same day file content multiple times."""
    seen = set()
    out = []
    for e in events:
        key = (e["ts"], e["msg"])
        if key in seen:
            continue
        seen.add(key)
        out.append(e)
    return out

def classify(msg: str) -> str | None:
    rules = [
        ("ORPHAN_KILL", r"ORPHAN_TUNNEL: killing"),
        ("ENSURE_SPAWN", r"ENSURE_TUNNEL spawned"),
        ("ENSURE_OK", r"ENSURE_TUNNEL ok=1"),
        ("ENSURE_FAIL", r"ENSURE_TUNNEL ok=0"),
        ("ENSURE_REUSE", r"ENSURE_TUNNEL reused=1"),
        ("SYNC_ALIVE", r"TUNNEL_SYNC: bg_alive"),
        ("SYNC_REATTACH", r"TUNNEL_SYNC ok=1 reason=reattached"),
        ("SYNC_SOFT", r"TUNNEL_SYNC soft_fail"),
        ("SYNC_DROP", r"TUNNEL_DROP"),
        ("SYNC_DOWN", r"TUNNEL_SYNC ok=0 reason=tunnel_down"),
        ("BANNER_BEGIN", r"TUNNEL_BANNER_BEGIN"),
        ("BANNER_MISS", r"TUNNEL_BANNER miss="),
        ("BANNER_HIT", r"TUNNEL_BANNER port=.*banner=SSH-2\.0-OpenSSH_for_Windows"),
        ("TUNNEL_UP_F", r"TUNNEL_UP port=.*up=False"),
        ("TUNNEL_UP_T", r"TUNNEL_UP port=.*up=True"),
        ("CONN_DROP", r"TUNNEL: connection dropped"),
        ("RECOVERY_B", r"RECOVERY_BEGIN"),
        ("CLEAR_MOUNT", r"CLEAR_MOUNT project="),
        ("CLEAR_DOWN", r"CLEAR_MOUNT: down end"),
        ("UNMOUNT", r"unmounted:"),
        ("OPEN_CUR_B", r"STEP begin: Opening Cursor"),
        ("OPEN_CUR_E", r"STEP end: Opening Cursor ok"),
        ("MOUNT_OK", r"STEP end: Mounting"),
        ("DIAG_TUNNEL", r"TUNNEL up=True|TUNNEL up=False"),
        ("SSH_NC", r"SSH_BEGIN cmd=timeout 3 nc"),
        ("SSH_NC_END", r"SSH_END exit=.*out=\(empty\)"),
        ("REFUSED", r"Connection refused"),
        ("SESSION_DISC", r"SESSION: disconnect"),
        ("TUNNEL_STOP", r"TUNNEL_STOP"),
    ]
    for name, pat in rules:
        if re.search(pat, msg):
            return name
    return None

def main():
    events = parse(LOG)
    print(f"RAW_EVENTS={len(events)}")
    uniq = dedupe_exact(events)
    print(f"DEDUPED_EVENTS={len(uniq)}  DUPLICATE_FRACTION={1-len(uniq)/max(1,len(events)):.3f}")

    # session ids
    sids = Counter(e["sid"] for e in uniq)
    print("SESSION_IDS:", dict(sids.most_common(10)))

    labeled = []
    for e in uniq:
        c = classify(e["msg"])
        if c:
            labeled.append({**e, "cls": c})

    print(f"LABELED={len(labeled)}")
    print("CLASS_COUNTS:", dict(Counter(x["cls"] for x in labeled).most_common()))

    # Focus window around first CONN_DROP
    drops = [x for x in labeled if x["cls"] == "CONN_DROP"]
    print(f"\nCONN_DROP_N={len(drops)}")
    if not drops:
        return
    t0 = drops[0]["ts"]
    win = [x for x in labeled if abs((x["ts"] - t0).total_seconds()) < 120]
    print(f"\n=== STATE TRACE ±120s around first drop {t0} ===")
    for x in win:
        dt = (x["ts"] - t0).total_seconds()
        print(f"{dt:+8.3f}s  {x['cls']:14s}  {x['msg'][:110]}")

    # Hypothesis H1: bg_alive then abruptly tunnel_down without soft_fail
    print("\n=== H1: path to tunnel_down (causal chain) ===")
    downs = [x for x in labeled if x["cls"] == "SYNC_DOWN"]
    for d in downs:
        prior = [x for x in labeled if x["ts"] < d["ts"] and x["ts"] > d["ts"] - timedelta(seconds=20)]
        print(f"\nDOWN at {d['ts']}")
        for x in prior[-15:]:
            print(f"  {(x['ts']-d['ts']).total_seconds():+7.3f}s {x['cls']:14s} {x['msg'][:100]}")

    # Timing: last SYNC_ALIVE -> first BANNER_BEGIN -> SYNC_DOWN
    print("\n=== H2: timing metrics (seconds) ===")
    for d in downs:
        alives = [x for x in labeled if x["cls"] == "SYNC_ALIVE" and x["ts"] <= d["ts"]]
        banners = [x for x in labeled if x["cls"] == "BANNER_BEGIN" and x["ts"] <= d["ts"] and x["ts"] > d["ts"] - timedelta(seconds=10)]
        opens = [x for x in labeled if x["cls"] == "OPEN_CUR_E" and x["ts"] <= d["ts"]]
        ensures = [x for x in labeled if x["cls"] == "ENSURE_OK" and x["ts"] <= d["ts"]]
        last_alive = alives[-1]["ts"] if alives else None
        first_banner = banners[0]["ts"] if banners else None
        last_open = opens[-1]["ts"] if opens else None
        last_ensure = ensures[-1]["ts"] if ensures else None
        def sec(a,b):
            return None if not a or not b else round((b-a).total_seconds(), 3)
        print({
            "drop": str(d["ts"]),
            "alive_to_banner": sec(last_alive, first_banner),
            "alive_to_down": sec(last_alive, d["ts"]),
            "open_to_drop": sec(last_open, d["ts"]),
            "ensure_to_drop": sec(last_ensure, d["ts"]),
            "banner_probes_in_10s": len(banners),
        })

    # H3: after CLEAR_MOUNT, unmount confirmed before ENSURE?
    print("\n=== H3: recovery ordering (must be CLEAR before ENSURE) ===")
    for d in downs:
        after = [x for x in labeled if x["ts"] >= d["ts"] and x["ts"] < d["ts"] + timedelta(seconds=90)]
        seq = [x["cls"] for x in after]
        print("seq:", " -> ".join(seq[:20]))
        # prove Clear before new ensure
        try:
            i_clear = seq.index("CLEAR_MOUNT")
            i_ensure = seq.index("ENSURE_OK")
            print(f"  CLEAR_idx={i_clear} ENSURE_idx={i_ensure} clear_before_ensure={i_clear < i_ensure}")
        except ValueError as ex:
            print("  incomplete seq", ex)

    # H4: Sync interval distribution while bg_alive
    deltas = []
    alives = [x for x in labeled if x["cls"] == "SYNC_ALIVE"]
    for a, b in zip(alives, alives[1:]):
        dt = (b["ts"] - a["ts"]).total_seconds()
        if 0 < dt < 5:
            deltas.append(dt)
    if deltas:
        deltas.sort()
        def pct(p):
            return deltas[int(len(deltas)*p/100)]
        print(f"\n=== H4: Sync tick interval while bg_alive n={len(deltas)} ===")
        print(f"  min={deltas[0]:.3f} p50={pct(50):.3f} p90={pct(90):.3f} p99={pct(99):.3f} max={deltas[-1]:.3f}")

    # H5: empty nc while claiming up shortly before
    print("\n=== H5: diagnostic TUNNEL up=True within 30s before drop? ===")
    for d in downs:
        diags = [x for x in labeled if "TUNNEL up=True" in x["msg"] and d["ts"] - timedelta(seconds=30) <= x["ts"] <= d["ts"]]
        print(f"  drop={d['ts']} prior_up_true={len(diags)}")
        for x in diags[-3:]:
            print(f"    {(x['ts']-d['ts']).total_seconds():+.1f}s {x['msg'][:120]}")

    # Confounder: duplicate log inflation
    print("\n=== CONFOUNDER: identical CONN_DROP line multiplicity in RAW ===")
    raw_drop = sum(1 for e in events if "TUNNEL: connection dropped" in e["msg"])
    print(f"  raw={raw_drop} deduped={len(drops)}")

if __name__ == "__main__":
    main()
