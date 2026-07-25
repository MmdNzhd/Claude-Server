#!/usr/bin/env python3
"""Validate Evidence Pack markdown files (evidence-gated-stages)."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REQUIRED = [
    "ID",
    "VERIFY",
    "RESEARCH",
    "RED_TEST",
    "IMPLEMENT",
    "GREEN_TEST",
    "RUNTIME_GATE",
    "ARTIFACT_SYNC",
    "GATE",
]

SECTION_RE = re.compile(r"^##\s+(.+?)\s*$", re.M)
ALIAS = {
    "RED": "RED_TEST",
    "GREEN": "GREEN_TEST",
    "LIVE_GATE": "RUNTIME_GATE",
}
GATE_LINE_RE = re.compile(r"STAGE_(?:<[^>\s]+>|[\w.-]+)_DONE")
CITATION_RE = re.compile(r"https?://|\.md\b|/docs/")
DEPLOY_RAN_RE = re.compile(r"deploy_ran\s*=\s*(yes|no)", re.I)
DEPLOY_RAN_NO_RE = re.compile(r"deploy_ran\s*=\s*no", re.I)
RELEASE_CMD_RE = re.compile(
    r"\b(deploy-client|claude-server install|publish\.ps1|docker push)\b", re.I
)
NA_REASON_RE = re.compile(r"\bN/A\b[^\n]*reason\s*=", re.I)


def normalize(name: str) -> str:
    n = name.strip().upper().replace(" ", "_")
    return ALIAS.get(n, n)


def section_bodies(text: str) -> dict[str, str]:
    matches = list(SECTION_RE.finditer(text))
    bodies: dict[str, str] = {}
    for i, m in enumerate(matches):
        name = normalize(m.group(1))
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        bodies.setdefault(name, text[start:end])
    return bodies


def _is_baseline_pack(id_body: str) -> bool:
    return bool(re.search(r"Stage:\s*`?0`?\b", id_body, re.I)) or bool(
        re.search(r"\bbaseline\b", id_body, re.I)
    )


def validate_text(text: str, *, strict: bool = False) -> list[str]:
    bodies = section_bodies(text)
    errors: list[str] = []

    missing = [s for s in REQUIRED if s not in bodies]
    if missing:
        errors.append("missing_sections=" + ",".join(missing))

    empty = [s for s in REQUIRED if s in bodies and not bodies[s].strip()]
    if empty:
        errors.append("empty_sections=" + ",".join(empty))

    id_body = bodies.get("ID", "")
    if "ID" in bodies and not DEPLOY_RAN_RE.search(id_body):
        errors.append("missing_deploy_ran")

    research = bodies.get("RESEARCH", "")
    if "RESEARCH" in bodies:
        citations = CITATION_RE.findall(research)
        if len(citations) < 2:
            errors.append("research_missing_urls_or_doc_paths")

    gate = bodies.get("GATE", "")
    if "GATE" in bodies and not GATE_LINE_RE.search(gate):
        errors.append("gate_missing_STAGE_DONE")

    if DEPLOY_RAN_NO_RE.search(text):
        claim_text = bodies.get("IMPLEMENT", "") + "\n" + bodies.get("VERIFY", "")
        if RELEASE_CMD_RE.search(claim_text):
            errors.append("deploy_ran_no_but_release_command_mentioned")

    runtime = bodies.get("RUNTIME_GATE", "")
    if "RUNTIME_GATE" in bodies:
        if re.search(
            r"signature_absent\s*=\s*yes\|pending|reason/proof:\s*`?\.\.\.`?|<session|<path:|<command>",
            runtime,
            re.I,
        ):
            errors.append("runtime_gate_template_placeholders")
        elif not re.search(
            r"(signature_absent\s*=\s*yes|pending_reconnect|\bN/A\b[^\n]*reason\s*=)",
            runtime,
            re.I,
        ):
            errors.append("runtime_gate_missing_proof_or_status")

    # GREEN without RED (skip baseline / explicit N/A reason on RED)
    red = bodies.get("RED_TEST", "")
    green = bodies.get("GREEN_TEST", "")
    if "RED_TEST" in bodies and "GREEN_TEST" in bodies and not _is_baseline_pack(id_body):
        red_na = bool(NA_REASON_RE.search(red))
        green_has_cmd = bool(re.search(r"```|Passed|pass|ok\b|exit\s*0", green, re.I))
        red_has_fail = bool(
            re.search(r"```|Failed|fail|error|Assertion|N/A", red, re.I)
        )
        if green_has_cmd and not red_has_fail and not red_na:
            errors.append("green_without_red_evidence")

    # ARTIFACT_SYNC must claim yes+SHA or n/a+reason
    art = bodies.get("ARTIFACT_SYNC", "")
    if "ARTIFACT_SYNC" in bodies:
        if re.search(r"artifact_sync\s*=\s*yes\|n/a|<list>|<roots", art, re.I):
            errors.append("artifact_sync_template_placeholders")
        elif not (
            re.search(r"artifact_sync\s*=\s*n/a", art, re.I)
            and re.search(r"reason\s*=", art, re.I)
        ) and not (
            re.search(r"artifact_sync\s*=\s*yes", art, re.I)
            and re.search(r"SHA|sha256|digest|version", art, re.I)
        ) and not (
            # allow n/a with reason without exact artifact_sync= key if reason present
            re.search(r"\bn/a\b", art, re.I) and re.search(r"reason\s*=", art, re.I)
        ):
            # soft: only in strict mode require full shape; default warn-as-error for empty-ish
            if strict or not re.search(r"(SHA|sha|digest|n/a|artifact_sync)", art, re.I):
                errors.append("artifact_sync_missing_sha_or_na_reason")

    # drive_by presence recommended in strict
    impl = bodies.get("IMPLEMENT", "")
    if strict and "IMPLEMENT" in bodies and not re.search(r"drive_by\s*=", impl, re.I):
        errors.append("implement_missing_drive_by")

    return errors


def validate_file(path: Path, *, strict: bool = False) -> int:
    if not path.is_file():
        print(f"MISSING_FILE {path}", file=sys.stderr)
        return 2
    errors = validate_text(
        path.read_text(encoding="utf-8", errors="replace"), strict=strict
    )
    if errors:
        print(f"INVALID {path.as_posix()}")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"VALID {path.as_posix()}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Validate evidence-gated-stages packs")
    ap.add_argument("path", nargs="?", help="Pack .md file")
    ap.add_argument("--dir", dest="dir", help="Directory of STAGE-*.md packs")
    ap.add_argument(
        "--strict",
        action="store_true",
        help="Extra checks: drive_by, stricter ARTIFACT_SYNC",
    )
    args = ap.parse_args()
    if args.dir:
        d = Path(args.dir)
        if not d.is_dir():
            print(f"MISSING_DIR {d}", file=sys.stderr)
            return 2
        paths = sorted(d.glob("STAGE-*.md"))
        if not paths:
            print(f"NO_PACKS {d}", file=sys.stderr)
            return 2
        rc = 0
        for p in paths:
            rc = max(rc, validate_file(p, strict=args.strict))
        return rc
    if not args.path:
        ap.print_help()
        return 2
    return validate_file(Path(args.path), strict=args.strict)


if __name__ == "__main__":
    raise SystemExit(main())
