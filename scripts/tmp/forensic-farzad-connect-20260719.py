#!/usr/bin/env python3
"""Forensic analysis of Farzad Sepidz connect-YYYYMMDD.log.

Usage:
  python forensic-farzad-connect-20260719.py [path-to-log]

Default path: scripts/tmp/farzad-connect-20260719.log
"""
from __future__ import annotations

import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

TS_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\]")
SID_RE = re.compile(r"\[([0-9a-f]{12})\]")
START_RE = re.compile(
    r"session start v(\S+) user=(\S+) elevated=(\S+) pid=(\d+)(?: session=(\S+))?"
)


def parse_ts(line: str):
    m = TS_RE.match(line)
    if not m:
        return None
    return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f")


def safe(s) -> str:
    return ("" if s is None else str(s)).encode("ascii", "backslashreplace").decode("ascii")


def main() -> int:
    # Force UTF-8 stdout when possible (Windows cp1252 breaks on Persian glyphs).
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    log_path = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/tmp/farzad-connect-20260719.log")
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    print(f"LOG={log_path} lines={len(lines)}")
    print(f"FIRST={safe(lines[0] if lines else '')}")
    print(f"LAST={safe(lines[-1] if lines else '')}")

    sessions = []
    cur = None
    for i, line in enumerate(lines, 1):
        if "======== session start" in line:
            m = START_RE.search(line)
            sid = (m.group(5) if m and m.group(5) else None) or (
                f"nosid-pid{m.group(4)}" if m else f"nosid-L{i}"
            )
            cur = {
                "sid": sid,
                "ver": m.group(1) if m else "?",
                "pid": m.group(4) if m else "?",
                "start_line": i,
                "start_ts": parse_ts(line),
                "project": None,
                "mount": None,
                "verdict": None,
                "end_line": None,
                "end_ts": None,
                "how": None,
                "status_ok": 0,
                "elif_err": 0,
            }
            sessions.append(cur)
        elif cur is None:
            continue
        elif "======== session end" in line:
            cur["end_line"] = i
            cur["end_ts"] = parse_ts(line)
            cur["how"] = cur["how"] or "session_end"
        elif "DECISION: project_select=" in line:
            pm = re.search(r"id=(\S+) path=(\S+)", line)
            if pm:
                cur["project"], cur["mount"] = pm.group(1), pm.group(2)
        elif "VERDICT_SUMMARY=" in line:
            cur["verdict"] = line.split("VERDICT_SUMMARY=", 1)[1].strip()
        elif "STATUS_OK" in line:
            cur["status_ok"] += 1
        elif "syntax error near unexpected token `elif'" in line:
            cur["elif_err"] += 1
        elif "DECISION: session_key=" in line:
            cur["how"] = f"quit:{line.split('DECISION: ',1)[1].strip()}"

    print("\n## SESSION TABLE")
    for n, s in enumerate(sessions, 1):
        dur = ""
        if s["start_ts"] and s["end_ts"]:
            dur = f"{(s['end_ts']-s['start_ts']).total_seconds():.0f}s"
        how = s["how"] or "NO_END (silent death / truncated)"
        print(
            f"{n}. sid={s['sid']} ver={s['ver']} start=L{s['start_line']} {s['start_ts']} "
            f"end=L{s['end_line']} {s['end_ts']} {dur} project={s['project']} mount={s['mount']} "
            f"STATUS_OK={s['status_ok']} elif={s['elif_err']} verdict={safe(s['verdict'])} how={safe(how)}"
        )

    def count(pat: str) -> int:
        return sum(1 for l in lines if re.search(pat, l))

    print("\n## COUNTS")
    for name, pat in [
        ("CLEAR_MOUNT project=", r"GITMODE: CLEAR_MOUNT project="),
        ("CLEAR_MOUNT all", r"CLEAR_MOUNT"),
        ("elif syntax error", r"syntax error near unexpected token `elif'"),
        ("ACTIVE_MOUNT server_conf= (mismatch-like)", r"ACTIVE_MOUNT server_conf="),
        ("STATUS_OK", r"STATUS_OK"),
        ("UPDATE lines", r"\] UPDATE:"),
        ("UPDATE up_to_date .21", r"up_to_date v20260719\.21"),
        ("UPDATE available -> .24", r"available .*-> v20260719\.24"),
        ("UPDATE .26", r"20260719\.26"),
        ("need_relaunch", r"need_relaunch"),
        ("soft_fail", r"soft_fail|SOFT_FAIL"),
        ("tunnel_down", r"tunnel_down|TUNNEL_DOWN"),
        ("RECOVERY", r"\bRECOVERY\b"),
        ("ENSURE_TUNNEL", r"ENSURE_TUNNEL"),
        ("ORPHAN_TUNNEL", r"ORPHAN_TUNNEL"),
        ("STALE_FORWARD", r"STALE_FORWARD"),
        ("WARN Enter a number", r"Enter a number or a/e/d/c/g/q"),
    ]:
        print(f"  {count(pat):4d}  {name}")

    print("\n## DECISION session_key")
    for i, line in enumerate(lines, 1):
        if "DECISION: session_key=" not in line:
            continue
        keychar = re.search(r"keychar=(\S+)", line)
        kc = keychar.group(1) if keychar else "?"
        if kc == "q":
            cls = "INTENTIONAL_OR_LATIN_LAYOUT (keychar=q)"
        elif kc == "\u0636":  # Persian dad / ض
            cls = "PERSIAN_LAYOUT_ON_PHYSICAL_Q (key=Q keychar=DAD) — accidental-quit candidate"
        else:
            cls = f"OTHER({safe(kc)})"
        print(f"  L{i}: {safe(line.strip())}")
        print(f"       classify={cls}")

    print("\n## STATUS_OK gaps >60s (same sid)")
    status = []
    for i, line in enumerate(lines, 1):
        if "STATUS_OK" not in line:
            continue
        sm = SID_RE.search(line)
        status.append((i, parse_ts(line), sm.group(1) if sm else "?"))
    for a, b in zip(status, status[1:]):
        if a[2] != b[2] or not a[1] or not b[1]:
            continue
        gap = (b[1] - a[1]).total_seconds()
        if gap > 60:
            print(f"  gap={gap:.1f}s sid={a[2]} L{a[0]}->{b[0]} intervening={b[0]-a[0]-1}")

    c = Counter(lines)
    dups = [(n, l) for l, n in c.items() if n > 1]
    print(f"\n## DUPLICATES exact ts+msg: distinct={len(dups)} extra={sum(n-1 for n,_ in dups)}")

    print("\n## .24/.26")
    print(f"  .26 mentions: {count(r'20260719\\.26')}")
    print(f"  .24 session starts: {sum(1 for l in lines if 'session start v20260719.24' in l)}")
    print(f"  .26 session starts: {sum(1 for l in lines if 'session start v20260719.26' in l)}")
    if any("need_relaunch" in l for l in lines):
        print("  need_relaunch present; check whether any post-update session start follows")
        for i, line in enumerate(lines, 1):
            if "need_relaunch" in line:
                print(f"  L{i}: {safe(line)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
