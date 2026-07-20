#!/usr/bin/env python3
"""Shared helpers for Claude OAuth deploy, sync audit, and API probes."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

AUTH_LOG = Path("/var/log/claude-auth.log")
# Root-only token store (mode 0600). Legacy /etc/environment is migrated away.
TOKEN_FILE = Path("/etc/claude-code/oauth.env")
ENV_FILE = Path("/etc/environment")  # legacy; token stripped on deploy
PROFILE_FILE = Path("/etc/profile.d/claude-auth.sh")
API_URL = "https://api.anthropic.com/v1/messages"
PROBE_MODEL = "claude-sonnet-4-20250514"
TOKEN_PREFIX = "sk-ant-oat01-"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def token_fingerprint(token: str | None) -> dict[str, Any]:
    """Non-secret summary for admin diagnostics. Never log raw token or prefix bytes."""
    if not token:
        return {"len": 0, "sha256": "", "present": False}
    digest = hashlib.sha256(token.encode("utf-8")).hexdigest()[:16]
    return {"len": len(token), "sha256": digest, "present": True}


def _parse_token_line(line: str) -> str:
    line = line.strip()
    if line.startswith("export "):
        line = line[7:].strip()
    if line.startswith("CLAUDE_CODE_OAUTH_TOKEN="):
        return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


def read_env_token() -> str:
    """Read OAuth token from root-only file; fall back to legacy /etc/environment."""
    for path in (TOKEN_FILE, ENV_FILE):
        if not path.is_file():
            continue
        try:
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                tok = _parse_token_line(line)
                if tok:
                    return tok
        except OSError:
            continue
    return ""


def validate_setup_token(token: str) -> None:
    token = (token or "").strip()
    if not token.startswith(TOKEN_PREFIX):
        raise ValueError(
            f"token must start with {TOKEN_PREFIX} (from: claude setup-token)"
        )
    if len(token) < 80:
        raise ValueError("token looks truncated (too short)")


def log_event(event: str, **fields: Any) -> None:
    AUTH_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = {"timestamp": utc_now(), "event": event, **fields}
    # Root-only audit log — fingerprints still must not include raw token bytes.
    if not AUTH_LOG.exists():
        AUTH_LOG.touch(mode=0o600)
        os.chmod(AUTH_LOG, 0o600)
    with AUTH_LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    try:
        os.chmod(AUTH_LOG, 0o600)
    except OSError:
        pass
    print(json.dumps(entry, ensure_ascii=False))


def probe_token(token: str | None = None, source: str = "probe") -> dict[str, Any]:
    token = (token or read_env_token()).strip()
    fp = token_fingerprint(token)
    if not token:
        result = {
            "ok": False,
            "http_status": 0,
            "error": "no_token",
            "source": source,
            "token": fp,
        }
        log_event("PROBE_FAIL", **result)
        return result

    body = json.dumps(
        {
            "model": PROBE_MODEL,
            "max_tokens": 8,
            "messages": [{"role": "user", "content": "reply OK"}],
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status = resp.status
            raw = resp.read(500).decode("utf-8", errors="replace")
        ok = 200 <= status < 300
        result = {
            "ok": ok,
            "http_status": status,
            "source": source,
            "token": fp,
            "body_preview": raw[:120],
        }
        log_event("PROBE_OK" if ok else "PROBE_FAIL", **result)
        return result
    except urllib.error.HTTPError as exc:
        raw = exc.read(500).decode("utf-8", errors="replace")
        result = {
            "ok": False,
            "http_status": exc.code,
            "error": "http_error",
            "source": source,
            "token": fp,
            "body_preview": raw[:120],
        }
        log_event("PROBE_FAIL", **result)
        return result
    except Exception as exc:  # noqa: BLE001 — log all probe failures
        result = {
            "ok": False,
            "http_status": 0,
            "error": str(exc),
            "source": source,
            "token": fp,
        }
        log_event("PROBE_FAIL", **result)
        return result


def _strip_token_from_file(path: Path) -> None:
    if not path.is_file():
        return
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return
    out = [
        ln
        for ln in lines
        if not ln.strip().startswith("CLAUDE_CODE_OAUTH_TOKEN=")
        and not ln.strip().startswith("export CLAUDE_CODE_OAUTH_TOKEN=")
    ]
    if out != lines:
        path.write_text("\n".join(out) + ("\n" if out else ""), encoding="utf-8")


def write_env_token(token: str) -> None:
    """Write token to root-only /etc/claude-code/oauth.env; strip legacy world-readable copies."""
    validate_setup_token(token)
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(TOKEN_FILE.parent, 0o700)
    TOKEN_FILE.write_text(f"CLAUDE_CODE_OAUTH_TOKEN={token}\n", encoding="utf-8")
    os.chmod(TOKEN_FILE, 0o600)
    # Remove world-readable copies (historical /etc/environment mode 644).
    _strip_token_from_file(ENV_FILE)


def write_profile_token(token: str) -> None:
    """Profile stub only — never put the token in world-readable profile.d."""
    validate_setup_token(token)
    PROFILE_FILE.write_text(
        "# Claude OAuth: token is root-only at /etc/claude-code/oauth.env\n"
        "# Per-user copies live in ~/.claude/settings.json (claude-auth-sync).\n"
        "# Do not export CLAUDE_CODE_OAUTH_TOKEN from this file.\n",
        encoding="utf-8",
    )
    os.chmod(PROFILE_FILE, 0o644)


def incident_snapshot(label: str = "baseline") -> None:
    """Record non-secret auth state for post-mortems."""
    users = []
    for pw in sorted(Path("/home").glob("*")):
        if not pw.is_dir():
            continue
        u = pw.name
        cred = pw / ".claude" / ".credentials.json"
        settings = pw / ".claude" / "settings.json"
        row: dict[str, Any] = {"user": u}
        if cred.is_file():
            row["credentials_bytes"] = cred.stat().st_size
            row["credentials_mtime"] = datetime.fromtimestamp(
                cred.stat().st_mtime, timezone.utc
            ).strftime("%Y-%m-%dT%H:%M:%SZ")
        if settings.is_file():
            try:
                data = json.loads(settings.read_text(encoding="utf-8"))
                env = data.get("env") if isinstance(data, dict) else {}
                if isinstance(env, dict):
                    tok = env.get("CLAUDE_CODE_OAUTH_TOKEN", "")
                    row["settings_token"] = token_fingerprint(str(tok))
                    row["settings_has_vscode_lm"] = bool(
                        str(env.get("ANTHROPIC_AUTH_TOKEN", "")).startswith("vscode-lm")
                    )
            except (json.JSONDecodeError, OSError):
                row["settings_error"] = True
        users.append(row)
    log_event(
        "INCIDENT_SNAPSHOT",
        label=label,
        env_token=token_fingerprint(read_env_token()),
        users=users,
    )


def deploy_token(token: str, actor: str = "deploy") -> dict[str, Any]:
    """Validate, write env + profile, return fingerprints (never logs raw token)."""
    token = token.strip()
    old = read_env_token()
    validate_setup_token(token)
    log_event(
        "DEPLOY_START",
        actor=actor,
        old_token=token_fingerprint(old),
        new_token=token_fingerprint(token),
    )
    write_env_token(token)
    write_profile_token(token)
    log_event("DEPLOY_WRITTEN", actor=actor, new_token=token_fingerprint(token))
    return {"old": token_fingerprint(old), "new": token_fingerprint(token)}


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "usage: claude-auth-lib.py {probe|snapshot|fingerprint|deploy} [args...]",
            file=sys.stderr,
        )
        return 2
    cmd = sys.argv[1]
    if cmd == "probe":
        result = probe_token(source=sys.argv[2] if len(sys.argv) > 2 else "manual")
        return 0 if result.get("ok") else 1
    if cmd == "snapshot":
        incident_snapshot(sys.argv[2] if len(sys.argv) > 2 else "baseline")
        return 0
    if cmd == "fingerprint":
        print(json.dumps(token_fingerprint(read_env_token())))
        return 0
    if cmd == "deploy":
        if len(sys.argv) < 3:
            print("usage: claude-auth-lib.py deploy <token>", file=sys.stderr)
            return 2
        deploy_token(sys.argv[2], actor=sys.argv[3] if len(sys.argv) > 3 else "cli")
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
