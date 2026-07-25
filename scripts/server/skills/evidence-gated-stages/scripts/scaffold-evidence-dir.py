#!/usr/bin/env python3
"""Scaffold docs/<feature>-evidence/ for evidence-gated-stages.

Callers: author-mode agents / humans. CLI only (argparse). No network API.
Writes STAGE-0.md, HYPOTHESES.md, CLOSEOUT.md, README.md under docs/<feature>-evidence/.
User instruction (verbatim): کامل ترش کنی

Usage:
  python3 scaffold-evidence-dir.py --root /path/to/repo --feature orders-nre
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
ASSETS = SKILL / "assets"


def main() -> int:
    ap = argparse.ArgumentParser(description="Scaffold evidence-gated-stages evidence dir")
    ap.add_argument("--root", required=True, help="Repo root")
    ap.add_argument("--feature", required=True, help="Feature slug")
    ap.add_argument("--force", action="store_true", help="Overwrite STAGE-0 / HYPOTHESES")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    dest = root / "docs" / f"{args.feature}-evidence"
    dest.mkdir(parents=True, exist_ok=True)

    stage0 = dest / "STAGE-0.md"
    if stage0.exists() and not args.force:
        print(f"EXISTS {stage0} (use --force)")
    else:
        text = (ASSETS / "STAGE-TEMPLATE.md").read_text(encoding="utf-8")
        text = text.replace("STAGE-<id>", "STAGE-0").replace("<id>", "0")
        stage0.write_text(text, encoding="utf-8")
        print(f"WROTE {stage0}")

    hyp = dest / "HYPOTHESES.md"
    if not hyp.exists() or args.force:
        h = (ASSETS / "HYPOTHESES-TEMPLATE.md").read_text(encoding="utf-8")
        h = h.replace("<feature>", args.feature)
        hyp.write_text(h, encoding="utf-8")
        print(f"WROTE {hyp}")

    score = dest / "CLOSEOUT.md"
    if not score.exists():
        shutil.copy(ASSETS / "CLOSEOUT-SCORECARD.md", score)
        print(f"WROTE {score}")

    readme = dest / "README.md"
    if not readme.exists():
        readme.write_text(
            f"# {args.feature} evidence\n\n"
            "Skill: evidence-gated-stages\n\n"
            "Validate:\n\n"
            "```bash\n"
            "python3 ~/.cursor/skills/evidence-gated-stages/scripts/"
            f"validate-pack.py --dir {dest}\n"
            "```\n",
            encoding="utf-8",
        )
        print(f"WROTE {readme}")

    print(f"DIR {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
