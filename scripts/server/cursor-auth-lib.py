#!/usr/bin/env python3
"""Shared helpers for Cursor golden auth export/sync/refresh."""

from __future__ import annotations

import base64
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

GOLDEN_DIR = Path("/etc/cursor-auth/golden")
AUTH_JSON = GOLDEN_DIR / "auth.json"
STORAGE_JSON = GOLDEN_DIR / "storage.json"
STATE_KEYS_JSON = GOLDEN_DIR / "state-keys.json"
MACHINE_ID_TXT = GOLDEN_DIR / "machine-id.txt"
EXPORTED_AT = GOLDEN_DIR / "exported-at"
SOURCE_HOST = GOLDEN_DIR / "source-host"
REFRESH_LOG = Path("/var/log/cursor-auth-refresh.log")

OAUTH_CLIENT_ID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

STATE_KEYS = [
    "cursorAuth/accessToken",
    "cursorAuth/refreshToken",
    "cursorAuth/cachedEmail",
    "cursorAuth/cachedSignUpType",
    "cursorAuth/stripeMembershipType",
    "cursorAuth/stripeSubscriptionStatus",
    "storage.serviceMachineId",
    "telemetry.machineId",
    "telemetry.macMachineId",
    "telemetry.devDeviceId",
    "telemetry.sqmId",
]

STORAGE_JSON_KEYS = [
    "telemetry.machineId",
    "telemetry.macMachineId",
    "telemetry.devDeviceId",
    "telemetry.sqmId",
]

AUTH_JSON_FIELDS = [
    "accessToken",
    "refreshToken",
    "cachedEmail",
    "stripeMembershipType",
    "stripeSubscriptionStatus",
]


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)"
    )


def _path_readable(path: Path) -> bool:
    try:
        return path.is_file()
    except OSError:
        return False


def _checkpoint_wal(db_path: Path) -> None:
    if not _path_readable(db_path):
        return
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute("PRAGMA wal_checkpoint(FULL)")
    except sqlite3.Error:
        pass
    finally:
        conn.close()


def read_state_value(db_path: Path, key: str) -> str | None:
    if not _path_readable(db_path):
        return None
    _checkpoint_wal(db_path)
    conn = sqlite3.connect(str(db_path))
    try:
        row = conn.execute(
            "SELECT value FROM ItemTable WHERE key = ?", (key,)
        ).fetchone()
        return row[0] if row else None
    except sqlite3.Error:
        return None
    finally:
        conn.close()


def read_relevant_state_values(db_path: Path) -> dict[str, str]:
    if not _path_readable(db_path):
        return {}
    _checkpoint_wal(db_path)
    conn = sqlite3.connect(str(db_path))
    try:
        _ensure_schema(conn)
        rows = conn.execute(
            """
            SELECT key, value FROM ItemTable
            WHERE key LIKE 'cursorAuth/%'
               OR key LIKE 'telemetry.%'
               OR key = 'storage.serviceMachineId'
            """
        ).fetchall()
        return {str(k): str(v) for k, v in rows if k and v}
    except sqlite3.Error:
        return {}
    finally:
        conn.close()


def read_state_values(db_path: Path, keys: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    if not _path_readable(db_path):
        return out
    _checkpoint_wal(db_path)
    conn = sqlite3.connect(str(db_path))
    try:
        _ensure_schema(conn)
        for key in keys:
            row = conn.execute(
                "SELECT value FROM ItemTable WHERE key = ?", (key,)
            ).fetchone()
            if row and row[0]:
                out[key] = row[0]
    finally:
        conn.close()
    return out


def upsert_state_values(db_path: Path, values: dict[str, str]) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    try:
        _ensure_schema(conn)
        for key, value in values.items():
            if value is None:
                continue
            conn.execute(
                "INSERT INTO ItemTable (key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, value),
            )
        conn.commit()
    finally:
        conn.close()


def load_storage_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def build_storage_json(state_values: dict[str, str], existing: dict[str, Any] | None = None) -> dict[str, Any]:
    data = dict(existing or {})
    for key in STORAGE_JSON_KEYS:
        short = key.split(".", 1)[-1]
        val = state_values.get(key) or state_values.get(f"telemetry.{short}")
        if val:
            data[key] = val
    return data


def jwt_expiry(token: str) -> int | None:
    try:
        parts = token.split(".")
        if len(parts) < 2:
            return None
        payload = parts[1]
        payload += "=" * (-len(payload) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")))
        exp = data.get("exp")
        return int(exp) if exp is not None else None
    except (ValueError, json.JSONDecodeError, OSError):
        return None


def jwt_expired(token: str, skew_seconds: int = 300) -> bool:
    exp = jwt_expiry(token)
    if exp is None:
        return False
    now = int(datetime.now(timezone.utc).timestamp())
    return exp <= now + skew_seconds


def golden_complete() -> bool:
    if not (
        AUTH_JSON.is_file()
        and STORAGE_JSON.is_file()
        and MACHINE_ID_TXT.is_file()
        and MACHINE_ID_TXT.read_text(encoding="utf-8").strip()
    ):
        return False
    try:
        auth = load_golden_auth()
    except (json.JSONDecodeError, OSError):
        return False
    return bool(auth.get("accessToken") and auth.get("refreshToken"))


def load_golden_auth() -> dict[str, Any]:
    with AUTH_JSON.open(encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def load_golden_machine_id() -> str:
    return MACHINE_ID_TXT.read_text(encoding="utf-8").strip()


def atomic_write(path: Path, content: str, mode: int = 0o640) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    os.close(fd)
    tmp_path = Path(tmp)
    try:
        tmp_path.write_text(content, encoding="utf-8")
        os.chmod(tmp, mode)
        tmp_path.replace(path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)


def write_golden_bundle(
    state_values: dict[str, str],
    storage_data: dict[str, Any],
    source_host: str,
    *,
    require_profile_metadata: bool = False,
) -> None:
    GOLDEN_DIR.mkdir(mode=0o700, exist_ok=True)
    os.chmod(GOLDEN_DIR, 0o700)

    auth_payload = {
        "accessToken": state_values.get("cursorAuth/accessToken", ""),
        "refreshToken": state_values.get("cursorAuth/refreshToken", ""),
        "cachedEmail": state_values.get("cursorAuth/cachedEmail", ""),
        "cachedSignUpType": state_values.get("cursorAuth/cachedSignUpType", ""),
        "stripeMembershipType": state_values.get("cursorAuth/stripeMembershipType", ""),
        "stripeSubscriptionStatus": state_values.get(
            "cursorAuth/stripeSubscriptionStatus", ""
        ),
    }

    machine_id = state_values.get("storage.serviceMachineId", "")
    if not machine_id:
        machine_id = state_values.get("telemetry.machineId", "")

    # Golden device: all telemetry IDs must match one virtual machine.
    for key in STORAGE_JSON_KEYS:
        if key not in storage_data and key not in state_values and machine_id:
            storage_data[key] = machine_id
            state_values[key] = machine_id

    missing = []
    if not auth_payload["accessToken"]:
        missing.append("cursorAuth/accessToken")
    if not auth_payload["refreshToken"]:
        missing.append("cursorAuth/refreshToken")
    if require_profile_metadata:
        if not auth_payload.get("cachedEmail"):
            missing.append("cursorAuth/cachedEmail")
        if not auth_payload.get("stripeMembershipType"):
            missing.append("cursorAuth/stripeMembershipType")
    if not machine_id:
        missing.append("storage.serviceMachineId")
    for key in STORAGE_JSON_KEYS:
        if key not in storage_data and key not in state_values:
            missing.append(key)
    if missing:
        raise SystemExit(
            "cursor-auth-export: missing required keys: " + ", ".join(missing)
        )

    # Secrets: root-only 0600. Metadata (machine-id, timestamps) also 0600 — directory is 0700.
    atomic_write(AUTH_JSON, json.dumps(auth_payload, indent=2) + "\n", mode=0o600)
    atomic_write(
        STATE_KEYS_JSON, json.dumps(state_values, indent=2) + "\n", mode=0o600
    )
    atomic_write(STORAGE_JSON, json.dumps(storage_data, indent=2) + "\n", mode=0o600)
    atomic_write(MACHINE_ID_TXT, machine_id + "\n", mode=0o600)
    atomic_write(
        EXPORTED_AT,
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") + "\n",
        mode=0o600,
    )
    atomic_write(SOURCE_HOST, source_host + "\n", mode=0o600)


def global_storage_dirs(home: Path) -> list[Path]:
    dirs = [
        home / ".config" / "Cursor" / "User" / "globalStorage",
        home / ".config" / "cursor" / "User" / "globalStorage",
        home / ".cursor-server" / "data" / "User" / "globalStorage",
    ]
    out: list[Path] = []
    seen: set[str] = set()
    for d in dirs:
        key = str(d)
        if key not in seen:
            seen.add(key)
            out.append(d)
    return out


def _secret_tool_lookup(username: str, service: str) -> str | None:
    if not shutil.which("secret-tool"):
        return None
    try:
        proc = subprocess.run(
            ["sudo", "-u", username, "secret-tool", "lookup", "service", service],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    return None


def read_agent_keychain(username: str) -> dict[str, str]:
    values: dict[str, str] = {}
    access = _secret_tool_lookup(username, "cursor-access-token")
    refresh = _secret_tool_lookup(username, "cursor-refresh-token")
    if access:
        values["cursorAuth/accessToken"] = access
    if refresh:
        values["cursorAuth/refreshToken"] = refresh
    return values


def read_agent_credential_files(home: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    candidates = [
        home / ".cursor" / "auth.json",
        home / ".cursor" / "credentials.json",
        home / ".config" / "cursor" / "auth.json",
        home / ".local" / "share" / "cursor" / "auth.json",
    ]
    for path in candidates:
        if not path.is_file():
            continue
        try:
            with path.open(encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue
        if not isinstance(data, dict):
            continue
        access = data.get("accessToken") or data.get("access_token")
        refresh = data.get("refreshToken") or data.get("refresh_token")
        email = data.get("cachedEmail") or data.get("email")
        if access:
            values["cursorAuth/accessToken"] = str(access)
        if refresh:
            values["cursorAuth/refreshToken"] = str(refresh)
        if email:
            values["cursorAuth/cachedEmail"] = str(email)
        if values.get("cursorAuth/accessToken") and values.get("cursorAuth/refreshToken"):
            return values
    return values


def new_golden_machine_id() -> str:
    return str(uuid.uuid4())


def export_from_global_storage(global_dir: Path, source_host: str) -> None:
    db_path = global_dir / "state.vscdb"
    storage_path = global_dir / "storage.json"
    if not db_path.is_file():
        raise SystemExit(f"cursor-auth-export: state.vscdb not found: {db_path}")

    state_values = read_relevant_state_values(db_path)
    if not state_values:
        state_values = read_state_values(db_path, STATE_KEYS)
    existing_storage = load_storage_json(storage_path)
    storage_data = build_storage_json(state_values, existing_storage)
    write_golden_bundle(state_values, storage_data, source_host)


def _newest_agent_auth_mtime(home: Path) -> float:
    candidates = [
        home / ".cursor" / "auth.json",
        home / ".cursor" / "credentials.json",
        home / ".config" / "cursor" / "auth.json",
        home / ".local" / "share" / "cursor" / "auth.json",
    ]
    mtimes = [p.stat().st_mtime for p in candidates if p.is_file()]
    return max(mtimes, default=0.0)


def _best_global_storage_state(
    home: Path,
) -> tuple[Path | None, dict[str, str], float]:
    best_dir: Path | None = None
    best_values: dict[str, str] = {}
    best_mtime = 0.0
    for global_dir in global_storage_dirs(home):
        db_path = global_dir / "state.vscdb"
        if not db_path.is_file():
            continue
        mtime = db_path.stat().st_mtime
        if mtime >= best_mtime:
            values = read_relevant_state_values(db_path) or read_state_values(
                db_path, STATE_KEYS
            )
            if values:
                best_dir = global_dir
                best_values = values
                best_mtime = mtime
    return best_dir, best_values, best_mtime


def export_from_user(home: Path, username: str, source_host: str) -> str:
    """Export golden bundle from a user home. Returns source description."""
    global_dir, state_values, db_mtime = _best_global_storage_state(home)

    agent_values: dict[str, str] = {}
    agent_values.update(read_agent_keychain(username))
    if not agent_values.get("cursorAuth/accessToken"):
        agent_values.update(read_agent_credential_files(home))

    agent_mtime = _newest_agent_auth_mtime(home)
    if (
        agent_values.get("cursorAuth/accessToken")
        and agent_values.get("cursorAuth/refreshToken")
        and agent_mtime > db_mtime
    ):
        merged = dict(state_values)
        merged["cursorAuth/accessToken"] = agent_values["cursorAuth/accessToken"]
        merged["cursorAuth/refreshToken"] = agent_values["cursorAuth/refreshToken"]
        if agent_values.get("cursorAuth/cachedEmail"):
            merged["cursorAuth/cachedEmail"] = agent_values["cursorAuth/cachedEmail"]
        if global_dir:
            storage_path = global_dir / "storage.json"
            existing_storage = load_storage_json(storage_path)
            storage_data = build_storage_json(merged, existing_storage)
            write_golden_bundle(merged, storage_data, source_host)
            print(
                "cursor-auth-export: exported from agent auth "
                f"(newer than state.vscdb, mtime {agent_mtime:.0f} > {db_mtime:.0f})",
                file=sys.stderr,
            )
            return str(global_dir)
        machine_id = merged.get("storage.serviceMachineId") or new_golden_machine_id()
        merged["storage.serviceMachineId"] = machine_id
        for key in STORAGE_JSON_KEYS:
            merged.setdefault(key, machine_id)
        storage_data = build_storage_json(merged, {})
        write_golden_bundle(merged, storage_data, source_host)
        print(
            "cursor-auth-export: exported from agent auth files "
            f"(new golden machineId={machine_id})",
            file=sys.stderr,
        )
        return "agent-auth-files"

    if global_dir:
        export_from_global_storage(global_dir, source_host)
        return str(global_dir)

    state_values = dict(agent_values)

    if state_values.get("cursorAuth/accessToken") and state_values.get(
        "cursorAuth/refreshToken"
    ):
        machine_id = new_golden_machine_id()
        state_values["storage.serviceMachineId"] = machine_id
        for key in STORAGE_JSON_KEYS:
            state_values.setdefault(key, machine_id)
        storage_data = build_storage_json(state_values, {})
        write_golden_bundle(state_values, storage_data, source_host)
        print(
            "cursor-auth-export: exported from agent keychain/files "
            f"(new golden machineId={machine_id})",
            file=sys.stderr,
        )
        return "agent-keychain"

    searched = ", ".join(str(d / "state.vscdb") for d in global_storage_dirs(home))
    raise SystemExit(
        "cursor-auth-export: no Cursor IDE state.vscdb and no agent tokens found\n"
        f"  searched: {searched}\n"
        "  fix: run as that user: agent login\n"
        "       or connect once via Cursor Remote SSH from laptop"
    )


def state_values_from_golden() -> dict[str, str]:
    if STATE_KEYS_JSON.is_file():
        try:
            with STATE_KEYS_JSON.open(encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and data:
                values = {str(k): str(v) for k, v in data.items() if v}
                auth = load_golden_auth()
                if auth.get("accessToken"):
                    values["cursorAuth/accessToken"] = auth["accessToken"]
                if auth.get("refreshToken"):
                    values["cursorAuth/refreshToken"] = auth["refreshToken"]
                machine_id = load_golden_machine_id()
                if machine_id:
                    values["storage.serviceMachineId"] = machine_id
                    for key in STORAGE_JSON_KEYS:
                        if key not in values:
                            values[key] = machine_id
                return values
        except (json.JSONDecodeError, OSError):
            pass

    auth = load_golden_auth()
    machine_id = load_golden_machine_id()
    storage_data = load_storage_json(STORAGE_JSON)

    values: dict[str, str] = {}
    if auth.get("accessToken"):
        values["cursorAuth/accessToken"] = auth["accessToken"]
    if auth.get("refreshToken"):
        values["cursorAuth/refreshToken"] = auth["refreshToken"]
    if auth.get("cachedEmail"):
        values["cursorAuth/cachedEmail"] = auth["cachedEmail"]
    if auth.get("cachedSignUpType"):
        values["cursorAuth/cachedSignUpType"] = auth["cachedSignUpType"]
    if auth.get("stripeMembershipType"):
        values["cursorAuth/stripeMembershipType"] = auth["stripeMembershipType"]
    if auth.get("stripeSubscriptionStatus"):
        values["cursorAuth/stripeSubscriptionStatus"] = auth["stripeSubscriptionStatus"]
    if machine_id:
        values["storage.serviceMachineId"] = machine_id

    for key in STORAGE_JSON_KEYS:
        val = storage_data.get(key)
        if not val and machine_id:
            val = machine_id
        if val:
            values[key] = str(val)

    return values


def merge_user_storage_json(
    existing: dict[str, Any], golden_storage: dict[str, Any], machine_id: str
) -> dict[str, Any]:
    merged = dict(existing)
    for key in STORAGE_JSON_KEYS:
        val = golden_storage.get(key) or machine_id
        if val:
            merged[key] = val
    return merged


def _sync_global_dir(
    global_dir: Path,
    values: dict[str, str],
    golden_storage: dict[str, Any],
    machine_id: str,
    force: bool,
) -> None:
    global_dir.mkdir(parents=True, exist_ok=True)
    db_path = global_dir / "state.vscdb"
    storage_path = global_dir / "storage.json"

    wal_path = Path(str(db_path) + "-wal")
    if db_path.is_file() and wal_path.is_file() and not force:
        print(
            f"cursor-auth-sync: warning: {wal_path} exists — reload Cursor window after sync",
            file=sys.stderr,
        )
        _checkpoint_wal(db_path)

    upsert_state_values(db_path, values)
    existing_storage = load_storage_json(storage_path)
    merged_storage = merge_user_storage_json(
        existing_storage, golden_storage, machine_id
    )
    atomic_write(
        storage_path, json.dumps(merged_storage, indent=2) + "\n", mode=0o600
    )
    if db_path.is_file():
        os.chmod(db_path, 0o600)


def _chown_tree(path: Path, user: str, dir_mode: int = 0o700, file_mode: int = 0o600) -> None:
    if not path.exists():
        return
    try:
        for root, _dirs, files in os.walk(path):
            shutil.chown(root, user, user)
            os.chmod(root, dir_mode)
            for name in files:
                fpath = Path(root) / name
                shutil.chown(str(fpath), user, user)
                os.chmod(fpath, file_mode)
    except OSError:
        pass


def _chown_cursor_tree(home: Path, user: str) -> None:
    config_dir = home / ".config"
    if config_dir.exists():
        try:
            if os.stat(config_dir).st_uid == 0:
                os.chmod(config_dir, 0o755)
                shutil.chown(config_dir, user, user)
        except OSError:
            pass

    for sub in ("Cursor", "cursor"):
        _chown_tree(config_dir / sub, user)

    # Remote-SSH reads auth from ~/.cursor-server/data/User/globalStorage/
    server_chain = [
        home / ".cursor-server",
        home / ".cursor-server" / "data",
        home / ".cursor-server" / "data" / "User",
    ]
    for link in server_chain:
        if link.exists():
            try:
                shutil.chown(link, user, user)
                os.chmod(link, 0o700)
            except OSError:
                pass
    _chown_tree(
        home / ".cursor-server" / "data" / "User" / "globalStorage",
        user,
    )


def sync_user_home(home: Path, owner: str | None = None, force: bool = False) -> None:
    if not golden_complete():
        raise SystemExit(
            "cursor-auth-sync: golden bundle missing — run: sudo cursor-auth-export --from-user <name>"
        )

    values = state_values_from_golden()
    golden_storage = load_storage_json(STORAGE_JSON)
    machine_id = load_golden_machine_id()

    for global_dir in global_storage_dirs(home):
        _sync_global_dir(global_dir, values, golden_storage, machine_id, force)

    if owner:
        user = owner.split(":")[0]
        _chown_cursor_tree(home, user)


def user_machine_id(home: Path) -> str | None:
    for global_dir in global_storage_dirs(home):
        db_path = global_dir / "state.vscdb"
        mid = read_state_value(db_path, "storage.serviceMachineId")
        if mid:
            return mid
    return None


def user_has_tokens(home: Path) -> bool:
    for global_dir in global_storage_dirs(home):
        db_path = global_dir / "state.vscdb"
        access = read_state_value(db_path, "cursorAuth/accessToken")
        refresh = read_state_value(db_path, "cursorAuth/refreshToken")
        if access and refresh:
            return True
    return False


def laptop_source_relative_path(home: Path | None = None) -> str | None:
    """Relative path to globalStorage dir that has golden Cursor tokens (for laptop scp)."""
    home = home or Path.home()
    for global_dir in global_storage_dirs(home):
        db_path = global_dir / "state.vscdb"
        access = read_state_value(db_path, "cursorAuth/accessToken")
        refresh = read_state_value(db_path, "cursorAuth/refreshToken")
        if access and refresh:
            try:
                return global_dir.relative_to(home).as_posix()
            except ValueError:
                continue
    return None


def import_golden_from_laptop_dir(import_dir: Path, source_host: str) -> None:
    """Import golden bundle pushed from laptop ClaudeServerCursorProfile only."""
    auth_path = import_dir / "auth.json"
    state_path = import_dir / "state-keys.json"
    if not auth_path.is_file() or not state_path.is_file():
        raise SystemExit(
            "cursor-auth-import-laptop: missing auth.json or state-keys.json in "
            f"{import_dir}"
        )
    try:
        auth = json.loads(auth_path.read_text(encoding="utf-8"))
        state_values = json.loads(state_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        raise SystemExit(f"cursor-auth-import-laptop: invalid JSON: {exc}") from exc
    if not isinstance(auth, dict) or not isinstance(state_values, dict):
        raise SystemExit("cursor-auth-import-laptop: auth.json and state-keys.json must be objects")

    for src, dst in (
        ("accessToken", "cursorAuth/accessToken"),
        ("refreshToken", "cursorAuth/refreshToken"),
        ("cachedEmail", "cursorAuth/cachedEmail"),
        ("cachedSignUpType", "cursorAuth/cachedSignUpType"),
        ("stripeMembershipType", "cursorAuth/stripeMembershipType"),
        ("stripeSubscriptionStatus", "cursorAuth/stripeSubscriptionStatus"),
    ):
        val = auth.get(src) or state_values.get(dst)
        if val:
            state_values[dst] = str(val)

    machine_id = (
        state_values.get("storage.serviceMachineId")
        or load_golden_machine_id()
        or new_golden_machine_id()
    )
    state_values["storage.serviceMachineId"] = machine_id
    for key in STORAGE_JSON_KEYS:
        state_values.setdefault(key, machine_id)

    storage_path = import_dir / "storage.json"
    if storage_path.is_file():
        storage_data = load_storage_json(storage_path)
    else:
        storage_data = load_storage_json(STORAGE_JSON)
    storage_data = merge_user_storage_json({}, storage_data, machine_id)

    write_golden_bundle(
        state_values,
        storage_data,
        source_host,
        require_profile_metadata=True,
    )


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "source-path":
        rel = laptop_source_relative_path()
        if rel:
            print(rel)
            raise SystemExit(0)
        raise SystemExit(1)
    if len(sys.argv) >= 2 and sys.argv[1] == "laptop-auth-json":
        if not golden_complete():
            raise SystemExit(1)
        print(json.dumps(state_values_from_golden()))
        raise SystemExit(0)
    if len(sys.argv) >= 2 and sys.argv[1] == "import-laptop-dir":
        if len(sys.argv) < 3:
            raise SystemExit("usage: cursor-auth-lib.py import-laptop-dir <path>")
        import_dir = Path(sys.argv[2])
        source = sys.argv[3] if len(sys.argv) > 3 else "laptop-push"
        import_golden_from_laptop_dir(import_dir, source)
        print("OK")
        raise SystemExit(0)
