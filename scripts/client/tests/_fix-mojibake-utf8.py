#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Repair UTF-8 mojibake / BOM in repo files for fleet-safe client scripts.

Rules:
  - Strip UTF-8 BOM
  - One-shot reverse classic L1 mojibake (cp1252 misread of UTF-8 punct, re-saved as UTF-8)
  - Then ASCII-normalize remaining punctuation / deep mojibake leftovers
  - Write UTF-8 no BOM, preserve original newline style (CRLF if file had CRLF)

Usage:
  python scripts/client/tests/_fix-mojibake-utf8.py [--dry-run] [paths...]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# L0 punctuation -> build L1 on-disk pattern via cp1252 (or latin-1 fallback)
L0_CHARS = {
    "\u2014": "EMDASH",  # —
    "\u2013": "ENDASH",  # –
    "\u2018": "LSQUO",
    "\u2019": "RSQUO",
    "\u201c": "LDQUO",
    "\u201d": "RDQUO",
    "\u2026": "ELLIPS",
    "\u2192": "RARR",
    "\u2190": "LARR",
}


def l1_of(ch: str) -> str:
    b = ch.encode("utf-8")
    try:
        return b.decode("cp1252").encode("utf-8").decode("utf-8")
    except UnicodeDecodeError:
        return b.decode("latin-1").encode("utf-8").decode("utf-8")


L1_TO_L0 = {l1_of(ch): ch for ch in L0_CHARS}

# After L1 reverse, map unicode punct to ASCII for script safety
ASCII_MAP = {
    "\u2014": "-",
    "\u2013": "-",
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2026": "...",
    "\u2192": "->",
    "\u2190": "<-",
    "\u00a0": " ",
    "\u009d": "",  # control from deep/latin-1 peels
    "\u201a": ",",  # single low-9 quote leftover
    "\u0153": "oe",
    "\u0161": "s",
}

# Deep mojibake display forms commonly seen in this repo (after UTF-8 decode)
# Replace longest-first.
DEEP_REPLACEMENTS = [
    # classic deep emdash / arrow / quotes chains seen in CLAUDE.md / docs
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â\u009d", "-"),
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â", "-"),
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“", "-"),
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢", "'"),
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ", '"'),
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â", '"'),
    ("ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦", "..."),
    ("ÃƒÂ¢Ã¢â‚¬Â\u009dÃ¢â€šÂ¬", "-"),
    ("ÃƒÂ¢Ã¢â‚¬Â\u009d", "-"),
    ("ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢", "->"),
    ("ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬Å“", "<-"),
    ("Ã¢â€šÂ¬Ã¢â‚¬Â", "-"),
    ("Ã¢â€šÂ¬Ã¢â‚¬Å“", "-"),
    ("Ã¢â€šÂ¬Ã¢â€žÂ¢", "'"),
    ("Ã¢â‚¬Â", "-"),
    ("Ã¢â‚¬Å“", "-"),
    ("Ã¢â‚¬Â¦", "..."),
    ("Ã¢â‚¬â„¢", "'"),
    ("Ã¢â‚¬Å“", '"'),
    ("Ã¢â‚¬Â\u009d", "-"),
    ("â€”", "-"),
    ("â€“", "-"),
    ("â€™", "'"),
    ("â€˜", "'"),
    ("â€œ", '"'),
    ("â€\u009d", '"'),
    ("â€", '"'),
    ("â€¦", "..."),
    ("â†’", "->"),
    ("â†", "<-"),
    ("Ã¢â‚¬Â Ã¢â‚¬â„¢", "->"),
    ("Ã¢â‚¬Â Ã¢â‚¬Å“", "<-"),
]


DEFAULT_PATHS = [
    # runtime / shipped
    "scripts/client/windows/windows-mcp-laptop.ps1",
    "scripts/client/windows/connect-update.ps1",
    "scripts/client/connect-ui.ps1",
    "scripts/client/editor-launch.ps1",
    "scripts/client/users/designer/README.md",
    "scripts/server/cursor-auth-lib.py",
    "publish/publish.ps1",
    "publish/build-windows-exe.ps1",
    "scripts/client/tests/test-hardest-live-windows-mcp-chaos.ps1",
    "scripts/client/tests/test-session-fresh-ttl-matrix.ps1",
    # docs / project rules
    "CLAUDE.md",
    "docs/client-connect.md",
    "docs/connect-fix-evidence/STAGE-6b.md",
    ".superpowers/sdd/briefs/task-3-4-brief.md",
]


def oneshot_l1(text: str) -> str:
    # Replace L1 mojibake substrings with true unicode punct first
    # Sort longest L1 first
    for l1, l0 in sorted(L1_TO_L0.items(), key=lambda kv: -len(kv[0])):
        if l1 in text:
            text = text.replace(l1, l0)
    return text


def deep_and_ascii(text: str) -> str:
    for old, new in sorted(DEEP_REPLACEMENTS, key=lambda kv: -len(kv[0])):
        if old in text:
            text = text.replace(old, new)
    # Remaining mapped chars
    out = []
    for ch in text:
        if ch in ASCII_MAP:
            out.append(ASCII_MAP[ch])
        elif ord(ch) < 32 and ch not in "\t\n\r":
            # drop other controls
            continue
        elif ord(ch) > 127:
            # leftover high junk from deep chains: drop
            # keep rare intentional unicode? for this fleet fix, strip to ASCII-safe
            continue
        else:
            out.append(ch)
    text = "".join(out)
    # collapse odd leftovers like A->A->
    text = text.replace("A->A->", "->")
    text = re.sub(r"[ \t]+\n", "\n", text)
    return text


def repair_bytes(raw: bytes) -> tuple[bytes, dict]:
    stats = {"bom": False, "l1": 0, "deep_or_ascii": 0, "changed": False}
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
        stats["bom"] = True
    # detect newline style
    crlf = b"\r\n" in raw
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        stats["error"] = "invalid_utf8"
        return raw, stats

    orig = text
    before_l1 = text
    text = oneshot_l1(text)
    if text != before_l1:
        stats["l1"] = 1

    before_ascii = text
    text = deep_and_ascii(text)
    if text != before_ascii:
        stats["deep_or_ascii"] = 1

    if text != orig or stats["bom"]:
        stats["changed"] = True
        data = text.encode("utf-8")
        # normalize newlines to original dominant style
        if crlf:
            data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        else:
            data = data.replace(b"\r\n", b"\n")
        return data, stats
    return raw if not stats["bom"] else text.encode("utf-8"), stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("paths", nargs="*")
    args = ap.parse_args()
    root = Path(args.root)
    paths = args.paths or DEFAULT_PATHS

    changed = 0
    for rel in paths:
        p = root / rel
        if not p.exists():
            print(f"MISS {rel}")
            continue
        raw = p.read_bytes()
        new, st = repair_bytes(raw)
        if st.get("error"):
            print(f"SKIP_INVALID {rel}")
            continue
        if not st["changed"]:
            print(f"OK   {rel}")
            continue
        print(
            f"FIX  {rel} bom={int(st['bom'])} l1={st['l1']} ascii={st['deep_or_ascii']} "
            f"delta={len(new)-len(raw)}"
        )
        if not args.dry_run:
            p.write_bytes(new)
        changed += 1
    print(f"DONE changed={changed} dry_run={int(args.dry_run)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
