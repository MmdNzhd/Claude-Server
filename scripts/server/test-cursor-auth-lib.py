#!/usr/bin/env python3
"""Local self-test for cursor-auth-lib (no server required)."""

from __future__ import annotations

import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
LIB_PATH = REPO / "scripts" / "server" / "cursor-auth-lib.py"
import importlib.util

spec = importlib.util.spec_from_file_location("cursor_auth_lib", LIB_PATH)
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)


def make_state_db(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute(
        "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)"
    )
    for k, v in values.items():
        conn.execute("INSERT INTO ItemTable VALUES (?, ?)", (k, v))
    conn.commit()
    conn.close()


def main() -> int:
    errors = 0

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        golden = tmp_path / "golden"
        home_a = tmp_path / "home" / "smart"
        home_b = tmp_path / "home" / "amir"
        source_gs = tmp_path / "source" / "globalStorage"

        lib.GOLDEN_DIR = golden
        lib.AUTH_JSON = golden / "auth.json"
        lib.STORAGE_JSON = golden / "storage.json"
        lib.STATE_KEYS_JSON = golden / "state-keys.json"
        lib.MACHINE_ID_TXT = golden / "machine-id.txt"
        lib.EXPORTED_AT = golden / "exported-at"
        lib.SOURCE_HOST = golden / "source-host"

        mid = "golden-machine-id-12345"
        tokens = {
            "cursorAuth/accessToken": "eyJhbGci.test.access",
            "cursorAuth/refreshToken": "eyJhbGci.test.refresh",
            "cursorAuth/cachedEmail": "team@example.com",
            "storage.serviceMachineId": mid,
        }
        make_state_db(source_gs / "state.vscdb", tokens)
        (source_gs / "storage.json").write_text(
            json.dumps({"telemetry.machineId": mid}) + "\n",
            encoding="utf-8",
        )

        try:
            lib.export_from_global_storage(source_gs, "test-host")
        except SystemExit as exc:
            print(f"FAIL export: {exc}")
            return 1

        if not lib.golden_complete():
            print("FAIL golden_complete after export")
            errors += 1

        if not lib.STATE_KEYS_JSON.is_file():
            print("FAIL state-keys.json missing after export")
            errors += 1
        else:
            state_keys = json.loads(lib.STATE_KEYS_JSON.read_text(encoding="utf-8"))
            if state_keys.get("cursorAuth/accessToken") != tokens["cursorAuth/accessToken"]:
                print("FAIL state-keys.json missing accessToken")
                errors += 1
            if state_keys.get("cursorAuth/cachedSignUpType") is not None:
                pass  # optional key from source db

        storage = json.loads(lib.STORAGE_JSON.read_text(encoding="utf-8"))
        for key in lib.STORAGE_JSON_KEYS:
            if storage.get(key) != mid:
                print(f"FAIL storage.json missing unified {key}")
                errors += 1

        owner = None if os.name == "nt" else "smart:smart"
        lib.sync_user_home(home_a, owner)
        lib.sync_user_home(home_b, None if os.name == "nt" else "amir:amir")

        for user, home in (("smart", home_a), ("amir", home_b)):
            got = lib.user_machine_id(home)
            if got != mid:
                print(f"FAIL {user} machineId: expected {mid}, got {got}")
                errors += 1
            if not lib.user_has_tokens(home):
                print(f"FAIL {user} missing tokens after sync")
                errors += 1

        if os.name != "nt":
            import pwd

            expected_uid = os.getuid()
            if owner:
                expected_uid = pwd.getpwnam(owner.split(":")[0]).pw_uid
            for rel in (
                ".config/Cursor/User/globalStorage/state.vscdb",
                ".config/cursor/User/globalStorage/state.vscdb",
                ".cursor-server/data/User/globalStorage/state.vscdb",
            ):
                db = home_a / rel
                if not db.is_file():
                    print(f"FAIL missing synced db {rel}")
                    errors += 1
                    continue
                st = db.stat()
                if st.st_uid != expected_uid:
                    print(f"FAIL {rel} not owned by sync user (uid={st.st_uid}, expected={expected_uid})")
                    errors += 1

        # storage.json merge must preserve unrelated keys
        extra_gs = home_a / ".config" / "Cursor" / "User" / "globalStorage"
        (extra_gs / "storage.json").write_text(
            json.dumps({"some.other.key": "keep-me", "telemetry.machineId": "stale"}) + "\n",
            encoding="utf-8",
        )
        lib.sync_user_home(home_a, None)
        merged = json.loads((extra_gs / "storage.json").read_text(encoding="utf-8"))
        if merged.get("some.other.key") != "keep-me":
            print("FAIL storage.json merge dropped unrelated keys")
            errors += 1
        if merged.get("telemetry.machineId") != mid:
            print("FAIL storage.json merge did not update telemetry.machineId")
            errors += 1

        # Incomplete golden storage.json still syncs telemetry from machine-id.txt
        lib.STORAGE_JSON.write_text("{}\n", encoding="utf-8")
        vals = lib.state_values_from_golden()
        for key in lib.STORAGE_JSON_KEYS:
            if vals.get(key) != mid:
                print(f"FAIL state_values_from_golden fallback for {key}")
                errors += 1

        # laptop source-path: prefer .config/Cursor over empty .cursor-server
        home_c = tmp_path / "home" / "carol"
        empty_gs = home_c / ".cursor-server" / "data" / "User" / "globalStorage"
        make_state_db(empty_gs / "state.vscdb", {"telemetry.machineId": "stale-remote"})
        good_gs = home_c / ".config" / "Cursor" / "User" / "globalStorage"
        make_state_db(good_gs / "state.vscdb", tokens)
        rel = lib.laptop_source_relative_path(home_c)
        if rel != ".config/Cursor/User/globalStorage":
            print(f"FAIL laptop_source_relative_path: expected .config/Cursor, got {rel}")
            errors += 1

        golden_mode = oct(os.stat(golden).st_mode & 0o777)
        if golden_mode != "0o755":
            print(f"WARN golden dir mode {golden_mode} (expected 755)")

        auth_mode = oct(os.stat(lib.AUTH_JSON).st_mode & 0o777)
        if auth_mode != "0o644":
            print(f"WARN auth.json mode {auth_mode} (expected 644)")

    if errors:
        print(f"{errors} test(s) failed")
        return 1
    print("OK all cursor-auth-lib self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
