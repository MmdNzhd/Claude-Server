#!/usr/bin/env python3
"""Deep Cursor golden audit — metadata only, no secrets."""
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

GOLDEN = Path("/etc/cursor-auth/golden")
LIB = Path("/usr/local/lib/claude-server/cursor-auth-lib.py")
REQUIRED = (
    "cursorAuth/accessToken",
    "cursorAuth/refreshToken",
    "cursorAuth/cachedEmail",
    "cursorAuth/stripeMembershipType",
)

def lens_from_db(db: Path) -> dict[str, int]:
    if not db.is_file():
        return {}
    c = sqlite3.connect(str(db))
    try:
        rows = c.execute(
            "SELECT key, length(value) FROM ItemTable WHERE key LIKE 'cursorAuth/%'"
        ).fetchall()
        return {str(k): int(v) for k, v in rows}
    except sqlite3.Error:
        return {}
    finally:
        c.close()


def user_status(home: Path) -> dict:
    paths = [
        home / ".config/Cursor/User/globalStorage/state.vscdb",
        home / ".cursor-server/data/User/globalStorage/state.vscdb",
    ]
    best: dict[str, int] = {}
    for p in paths:
        cur = lens_from_db(p)
        for k, v in cur.items():
            best[k] = max(best.get(k, 0), v)
    missing = [k for k in REQUIRED if best.get(k, 0) == 0]
    return {
        "complete": not missing,
        "missing": missing,
        "lens": {k: best.get(k, 0) for k in REQUIRED},
        "db_bytes": max((p.stat().st_size for p in paths if p.is_file()), default=0),
    }


def golden_status() -> dict:
    out: dict = {"exists": GOLDEN.is_dir()}
    auth = GOLDEN / "auth.json"
    sk = GOLDEN / "state-keys.json"
    if auth.is_file():
        data = json.loads(auth.read_text(encoding="utf-8"))
        out["auth_lens"] = {k: len(str(data.get(k) or "")) for k in (
            "accessToken", "refreshToken", "cachedEmail", "stripeMembershipType", "cachedSignUpType"
        )}
    if sk.is_file():
        skd = json.loads(sk.read_text(encoding="utf-8"))
        out["state_keys_count"] = len(skd) if isinstance(skd, dict) else 0
        out["state_cursor_lens"] = {
            k: len(str(skd.get(k) or "")) for k in REQUIRED if isinstance(skd, dict)
        }
    exp = GOLDEN / "exported-at"
    src = GOLDEN / "source-host"
    out["exported_at"] = exp.read_text(encoding="utf-8").strip() if exp.is_file() else ""
    out["source_host"] = src.read_text(encoding="utf-8").strip() if src.is_file() else ""
    missing = []
    if "auth_lens" in out:
        if not out["auth_lens"].get("cachedEmail"):
            missing.append("auth.json:cachedEmail")
        if not out["auth_lens"].get("stripeMembershipType"):
            missing.append("auth.json:stripeMembershipType")
    out["complete"] = not missing
    out["missing"] = missing
    return out


def main() -> int:
    print("=== GOLDEN ===")
    print(json.dumps(golden_status(), indent=2))

    if LIB.is_file():
        text = LIB.read_text(encoding="utf-8")
        print("LIB", json.dumps({
            "lines": text.count("\n") + 1,
            "laptop_auth_json": "laptop-auth-json" in text,
            "import_laptop_dir": "import-laptop-dir" in text,
        }, indent=2))

    print("=== USERS ===")
    complete = incomplete = 0
    for home in sorted(Path("/home").iterdir()):
        if not home.is_dir():
            continue
        st = user_status(home)
        if not st["lens"].get("cursorAuth/accessToken"):
            continue
        tag = "COMPLETE" if st["complete"] else "INCOMPLETE"
        if st["complete"]:
            complete += 1
        else:
            incomplete += 1
        print(home.name, tag, json.dumps(st, separators=(",", ":")))
    print("=== SUMMARY ===")
    print(json.dumps({"users_with_tokens": complete + incomplete, "complete": complete, "incomplete": incomplete}))
    return 0 if incomplete == 0 and golden_status().get("complete") else 1


if __name__ == "__main__":
    raise SystemExit(main())
