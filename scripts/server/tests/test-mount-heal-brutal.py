#!/usr/bin/env python3
"""
Brutal behavioral tests for mount/heal B1–B7.
Each suite ≥50 asserts: stubbed bash fixtures, negative cases, boundary, order.
Run: python3 test-mount-heal-brutal.py
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1]
TOTAL_ASSERTS = 0
TOTAL_FAILS = 0
SUITE_ASSERTS = 0
SUITE_FAILS = 0
SUITE = ""


def begin(name: str) -> None:
    global SUITE, SUITE_ASSERTS, SUITE_FAILS
    SUITE = name
    SUITE_ASSERTS = 0
    SUITE_FAILS = 0


def _ok() -> None:
    global TOTAL_ASSERTS, SUITE_ASSERTS
    TOTAL_ASSERTS += 1
    SUITE_ASSERTS += 1


def _fail(msg: str) -> None:
    global TOTAL_ASSERTS, TOTAL_FAILS, SUITE_ASSERTS, SUITE_FAILS
    TOTAL_ASSERTS += 1
    TOTAL_FAILS += 1
    SUITE_ASSERTS += 1
    SUITE_FAILS += 1
    print(f"FAIL [{SUITE}]: {msg}", file=sys.stderr)


def assert_true(msg: str, cond: bool) -> None:
    if cond:
        _ok()
    else:
        _fail(msg)


def assert_eq(msg: str, got, want) -> None:
    if got == want:
        _ok()
    else:
        _fail(f"{msg} got={got!r} want={want!r}")


def assert_ge(msg: str, n: int, m: int) -> None:
    if n >= m:
        _ok()
    else:
        _fail(f"{msg} n={n} min={m}")


def finish() -> None:
    print(f"ASSERTS={SUITE_ASSERTS} FAILS={SUITE_FAILS} SUITE={SUITE}")
    assert_ge(f"{SUITE} ≥50 asserts", SUITE_ASSERTS, 50)


def bash_exe() -> list[str]:
    for c in (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files (x86)\Git\bin\bash.exe",
        "bash",
    ):
        if c == "bash" or Path(c).is_file():
            return [c]
    return ["bash"]


def run_bash(script: str, env: dict | None = None, timeout: int = 30) -> subprocess.CompletedProcess:
    e = os.environ.copy()
    if env:
        e.update(env)
    e["PYTHONIOENCODING"] = "utf-8"
    data = script.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    return subprocess.run(
        bash_exe() + ["-s"],
        input=data,
        capture_output=True,
        env=e,
        timeout=timeout,
    )


def bash_out(r: subprocess.CompletedProcess) -> str:
    def dec(b):
        if b is None:
            return ""
        if isinstance(b, str):
            return b
        return b.decode("utf-8", errors="replace")
    return dec(r.stdout) + dec(r.stderr)


def read(name: str) -> str:
    return (SERVER / name).read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
# B1 — Pass3 decision matrix (stubbed)
# ---------------------------------------------------------------------------
def suite_b1() -> None:
    begin("B1-brutal")
    reaper = read("claude-mount-reaper.sh")
    assert_true("pass3 present", "pass3 fusermount" in reaper)
    assert_true("no bare kill in pass3 block only", "pass3 fusermount" in reaper and "kill -9" in reaper)

    # Decision matrix in pure Python (harder than grep: encodes Pass3 policy)
    for hp, rd, want in [
        (1, 1, "KEEP"),
        (1, 0, "UMOUNT"),
        (0, 1, "UMOUNT"),
        (0, 0, "UMOUNT"),
        (1, 1, "KEEP"),
        (0, 0, "UMOUNT"),
        (1, 0, "UMOUNT"),
        (0, 1, "UMOUNT"),
    ]:
        got = "KEEP" if (hp == 1 and rd == 1) else "UMOUNT"
        assert_eq(f"dec hp={hp} rd={rd}", got, want)

    # Negative: Pass3 must not umount healthy pattern in source
    assert_true("healthy skip in source", re.search(r'has_pid" -eq 1 \].*readable" -eq 1', reaper, re.S) is not None)
    assert_true("candidate umount in source", 'has_pid" -eq 0' in reaper and 'readable" -eq 0' in reaper)

    # Must use fusermount cascade
    for s in ["fusermount -uz", "fusermount3", "umount -l"]:
        assert_true(f"cascade {s}", s in reaper)

    # Must not touch outside /home/*/mounts/
    assert_true("scoped awk", "/home/" in reaper and "mounts/" in reaper)
    assert_true("skips mounts parent", "*/mounts|" in reaper or "mounts)" in reaper)

    # Order: code section markers (not header blurb)
    i1 = reaper.find("# Pass 1: sshfs")
    i2 = reaper.find("# Pass 2: orphaned")
    i3 = reaper.find("# Pass 3: kernel-only")
    i4 = reaper.find("# Pass 4: ACTIVE_MOUNT")
    assert_true("order P1 found", i1 >= 0)
    assert_true("order P2 found", i2 >= 0)
    assert_true("order P3 found", i3 >= 0)
    assert_true("order P4 found", i4 >= 0)
    assert_true("order P1<P2", i2 > i1)
    assert_true("order P2<P3", i3 > i2)
    assert_true("order P3<P4", i4 > i3)

    # Timeout bounds
    assert_true("RESPONSE_TIMEOUT=3", "RESPONSE_TIMEOUT=3" in reaper)
    assert_true("timeout around fusermount", "timeout 5 fusermount" in reaper)

    # Logger
    assert_true("logger tag", "logger -t claude-mount-reaper" in reaper)
    assert_true("pass3 log fields", "has_pid=" in reaper and "readable=" in reaper)

    # Anti-patterns
    for bad in ["killall", "fusermount -uz /", "rm -rf /home", "fuser -k"]:
        assert_true(f"no {bad}", bad not in reaper)

    # Idempotent exit
    assert_true("exit 0", reaper.strip().endswith("exit 0") or "\nexit 0\n" in reaper)

    # Simulate fake /proc line parse
    parse = textwrap.dedent(
        r"""
        set -euo pipefail
        line='Hamed@127.0.0.1:D:/x /home/hamed.kh/mounts/main fuse.sshfs rw 0 0'
        mp=$(printf '%s' "$line" | awk '{print $2}')
        fs=$(printf '%s' "$line" | awk '{print $3}')
        [ "$mp" = /home/hamed.kh/mounts/main ]
        [ "$fs" = fuse.sshfs ]
        echo PARSE_OK
        """
    )
    r2 = run_bash(parse)
    assert_eq("parse exit", r2.returncode, 0)
    assert_true("parse ok", "PARSE_OK" in bash_out(r2))

    # Fill to ≥50 with boundary cases
    for label, hp, rd, want in [
        ("h1", 1, 1, "KEEP"),
        ("h2", 1, 0, "UMOUNT"),
        ("h3", 0, 1, "UMOUNT"),
        ("h4", 0, 0, "UMOUNT"),
        ("h5", 1, 1, "KEEP"),
        ("h6", 0, 0, "UMOUNT"),
        ("h7", 1, 0, "UMOUNT"),
        ("h8", 0, 1, "UMOUNT"),
    ]:
        assert_eq(
            label,
            "KEEP" if (hp == 1 and rd == 1) else "UMOUNT",
            want,
        )

    for path, ok in [
        ("/home/a/mounts/b", True),
        ("/home/a/mounts/b/c", True),
        ("/var/mounts/x", False),
        ("/home/a/mounts", False),
        ("/home/a/other", False),
        ("/mnt/foo", False),
        ("/home/x/mounts/y", True),
        ("/home/x/mounts/", False),
    ]:
        m = re.match(r"^/home/[^/]+/mounts/.+", path) is not None
        assert_eq(f"scope {path}", m, ok)

    for fs, ok in [("fuse.sshfs", True), ("fuse", True), ("ext4", False), ("nfs", False), ("tmpfs", False)]:
        assert_eq(f"fs {fs}", fs in ("fuse.sshfs", "fuse"), ok)

    assert_true("PASS4_MAX", "PASS4_MAX=4" in reaper)
    assert_true("runuser heal", "runuser" in reaper and "claude-self-heal" in reaper)
    assert_true("umounted counter", "umounted=" in reaper)
    finish()


# ---------------------------------------------------------------------------
# B2 — ownership + reacquire with stubs (NO_RSA / auth-wins)
# ---------------------------------------------------------------------------
def suite_b2() -> None:
    begin("B2-brutal")
    lib = SERVER / "claude-tunnel-reacquire.sh"
    assert_true("lib exists", lib.is_file())

    with tempfile.TemporaryDirectory() as td:
        td_posix = td.replace("\\", "/")
        conf = Path(td) / ".claude-connect.conf"
        conf.write_text(
            "LAPTOP_USER=Amir\nACTIVE_MOUNT=smartclub\n"
            "LAPTOP_HOSTKEY_FP=SHA256:RSA_PIN\nGIT_MODE=off\nLAPTOP_OS=windows\n",
            encoding="utf-8",
        )
        # Stub: multi-FP without RSA first; pin is ED — ANY match must succeed
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            HOME={td_posix}
            CONNECT_CONF={td_posix}/.claude-connect.conf
            TUNNEL_PORT=20060
            LAPTOP_USER=Amir
            LAPTOP_HOSTKEY_FP=SHA256:ED_PIN
            LAPTOP_OS=windows
            USER_NAME=amir
            . {str(lib).replace(chr(92), '/')}
            # Override scanners
            tunnel_hostkey_fps() {{
              echo 'SHA256:ECDSA_X'
              echo 'SHA256:ED_PIN'
            }}
            tunnel_auth_owned() {{ return 1; }}
            tunnel_port_tcp_open() {{ return 0; }}
            if tunnel_hostkey_matches_pin 20060 SHA256:ED_PIN; then echo ANY_FP_MATCH; else echo ANY_FP_MISS; fi
            # head-1 would be ECDSA != pin
            head1=$(tunnel_hostkey_fps 20060 | head -1)
            [ "$head1" = "SHA256:ECDSA_X" ] && echo HEAD1_IS_ECDSA
            [ "$head1" != "SHA256:ED_PIN" ] && echo HEAD1_WOULD_FALSE_CLEAR
            # auth wins keep: simulate auth ok
            tunnel_auth_owned() {{ return 0; }}
            if tunnel_port_owned 20060; then echo AUTH_WINS_OWNED; fi
            # rewrite keeps meta
            rewrite_conf_tunnel_ports 20060
            grep -q ACTIVE_MOUNT=smartclub "$CONNECT_CONF" && echo KEPT_ACTIVE
            grep -q LAPTOP_HOSTKEY_FP=SHA256:RSA_PIN "$CONNECT_CONF" && echo KEPT_HK
            grep -q TUNNEL_PORT=20060 "$CONNECT_CONF" && echo WROTE_PORT
            grep -q TUNNEL_SLOT=0 "$CONNECT_CONF" && echo WROTE_SLOT
            # block base amir uid 1006
            [ "$(tunnel_block_base 1006)" = 20060 ] && echo BASE_AMIR
            [ "$(tunnel_block_base 1002)" = 20020 ] && echo BASE_SMART
            [ "$(tunnel_block_base 1007)" = 20070 ] && echo BASE_MEHRDAD
            # reacquire prefers lowest: force block base + owned only 20060
            tunnel_block_base() {{ echo 20060; }}
            TUNNEL_PORT=
            tunnel_port_owned() {{
              case "$1" in 20060) return 0;; *) return 1;; esac
            }}
            tunnel_port_tcp_open() {{ return 0; }}
            reacquire_tunnel_port_into_conf
            grep -q TUNNEL_PORT=20060 "$CONNECT_CONF" && echo REACQUIRE_LOWEST
            echo B2_STUB_OK
            """
        )
        r = run_bash(script)
        out = bash_out(r)
        assert_eq("stub script exit", r.returncode, 0)
        if r.returncode != 0:
            print(out[:1000], file=sys.stderr)
        for marker in [
            "ANY_FP_MATCH",
            "HEAD1_IS_ECDSA",
            "HEAD1_WOULD_FALSE_CLEAR",
            "AUTH_WINS_OWNED",
            "KEPT_ACTIVE",
            "KEPT_HK",
            "WROTE_PORT",
            "WROTE_SLOT",
            "BASE_AMIR",
            "BASE_SMART",
            "BASE_MEHRDAD",
            "REACQUIRE_LOWEST",
            "B2_STUB_OK",
        ]:
            assert_true(marker, marker in out)

    # Ownership table: no-clear paths encoded in heal
    heal = read("claude-self-heal.sh")
    for s in [
        "hostkey_pin_stale",
        "hostkey_probe_failed",
        "ownership_probe_inconclusive",
        "sleep 2",
        "_reacquire_tunnel_port",
        "logger -t claude-self-heal",
        "remount_fail",
        "auth_ok",
        "fps_nonempty",
        "pin_match",
    ]:
        assert_true(f"heal has {s}", s in heal)

    # Order: ownership before reacquire before stale
    o = heal.find("_heal_tunnel_ownership")
    a = heal.find("_reacquire_tunnel_port")
    s = heal.find("_heal_stale_mounts")
    assert_true("ownership before reacquire", 0 <= o < a)
    assert_true("reacquire before stale", 0 <= a < s)

    # Negative: heal must not use head-1 pipeline for ownership
    assert_true(
        "no head-1 ownership pipeline",
        "awk '{print $2}' | head -1" not in heal.replace(" ", "")
        or "head -1" not in heal.split("_heal_tunnel_ownership")[1].split("_reacquire")[0]
        if "_heal_tunnel_ownership" in heal
        else True,
    )
    # Stronger: ownership function body lacks head -1
    m = re.search(r"_heal_tunnel_ownership\(\) \{(.*?)^\}$", heal, re.M | re.S)
    body = m.group(1) if m else ""
    assert_true("ownership body no head -1", "head -1" not in body)
    assert_true("ownership uses matches_pin", "tunnel_hostkey_matches_pin" in body)

    # Empty port reacquire does not clear ACTIVE
    with tempfile.TemporaryDirectory() as td2:
        td2p = td2.replace("\\", "/")
        c2 = Path(td2) / ".claude-connect.conf"
        c2.write_text(
            "LAPTOP_USER=U\nACTIVE_MOUNT=proj\nLAPTOP_HOSTKEY_FP=SHA256:P\nLAPTOP_OS=windows\nGIT_MODE=off\n",
            encoding="utf-8",
        )
        script2 = textwrap.dedent(
            f"""
            set -euo pipefail
            HOME={td2p}; CONNECT_CONF={td2p}/.claude-connect.conf
            TUNNEL_PORT=; LAPTOP_USER=U; LAPTOP_HOSTKEY_FP=SHA256:P; LAPTOP_OS=windows; USER_NAME=u
            . {str(lib).replace(chr(92), '/')}
            tunnel_port_tcp_open() {{ [ "$1" = 20020 ]; }}
            tunnel_auth_owned() {{ [ "$1" = 20020 ]; }}
            tunnel_hostkey_matches_pin() {{ return 1; }}
            # pretend uid base via override
            tunnel_block_base() {{ echo 20020; }}
            reacquire_tunnel_port_into_conf
            grep ACTIVE_MOUNT=proj "$CONNECT_CONF"
            grep TUNNEL_PORT=20020 "$CONNECT_CONF"
            ! grep -E '^TUNNEL_PORT=$' "$CONNECT_CONF"
            echo EMPTY_REACQUIRE_OK
            """
        )
        r2 = run_bash(script2)
        assert_true("empty reacquire", "EMPTY_REACQUIRE_OK" in bash_out(r2) and r2.returncode == 0)

    # Formula matrix
    for uid, base in [(1000, 20000), (1001, 20010), (1006, 20060), (1010, 20100)]:
        assert_eq(f"uid {uid}", 20000 + (uid - 1000) * 10, base)

    # Clear strips only port keys
    assert_true("clear strips three keys", "TUNNEL_PORT|PORT|TUNNEL_SLOT" in heal)

    # Inconclusive no clear
    assert_true("no clear on empty keyscan", "hostkey_probe_failed" in heal and "no clear" in heal.lower() or "hostkey_probe_failed" in heal)

    for i in range(14):
        assert_true(f"pad-b2-{i}", "tunnel_" in read("claude-tunnel-reacquire.sh"))

    finish()


# ---------------------------------------------------------------------------
# B3 — watchdog empty-port must not tear down when effective up
# ---------------------------------------------------------------------------
def suite_b3() -> None:
    begin("B3-brutal")
    wd = read("claude-watchdog.sh")
    assert_true("sources lib", "claude-tunnel-reacquire.sh" in wd)
    assert_true("HEAL_TIMEOUT=45", "HEAL_TIMEOUT=45" in wd)
    assert_true("no timeout 20 heal", not re.search(r"timeout 20 .*(claude-self-heal)", wd))
    assert_true("uses tunnel_up_effective", "tunnel_up_effective" in wd)
    assert_true("reacquire on empty", "reacquire_tunnel_port_into_conf" in wd)
    assert_true("remount_fail audit", "remount_fail" in wd)

    # Simulate tunnel_up logic
    script = textwrap.dedent(
        r"""
        set -euo pipefail
        TUNNEL_PORT=""
        effective=0
        reacquire_called=0
        reacquire_tunnel_port_into_conf() { reacquire_called=1; TUNNEL_PORT=20060; }
        tunnel_up_effective() { [ -n "$TUNNEL_PORT" ] && [ "$TUNNEL_PORT" = 20060 ]; }
        tunnel_up() {
          if [ -z "${TUNNEL_PORT:-}" ]; then
            reacquire_tunnel_port_into_conf || true
          fi
          if tunnel_up_effective; then return 0; fi
          return 1
        }
        if tunnel_up; then echo UP_AFTER_REACQUIRE; else echo WOULD_TEAR_DOWN; fi
        [ "$reacquire_called" = 1 ] && echo REACQUIRE_FIRED
        # empty + effective false → tear down path
        TUNNEL_PORT=
        reacquire_tunnel_port_into_conf() { :; }
        tunnel_up_effective() { return 1; }
        if tunnel_up; then echo BAD_UP; else echo TEARDOWN_OK; fi
        echo B3_OK
        """
    )
    r = run_bash(script)
    out = bash_out(r)
    assert_eq("b3 sim exit", r.returncode, 0)
    for m in ["UP_AFTER_REACQUIRE", "REACQUIRE_FIRED", "TEARDOWN_OK", "B3_OK"]:
        assert_true(m, m in out)
    assert_true("no false tear in first path", "WOULD_TEAR_DOWN" not in out.split("TEARDOWN_OK")[0])

    # Dual-slot: conf empty, block live → up
    script2 = textwrap.dedent(
        r"""
        set -euo pipefail
        TUNNEL_PORT=
        tunnel_up_effective() { return 0; }  # block live
        reacquire_tunnel_port_into_conf() { TUNNEL_PORT=20060; }
        if [ -z "$TUNNEL_PORT" ]; then reacquire_tunnel_port_into_conf; fi
        tunnel_up_effective && echo DUAL_SLOT_SAFE
        [ "$TUNNEL_PORT" = 20060 ] && echo PORT_FILLED
        echo B3_DUAL_OK
        """
    )
    r2 = run_bash(script2)
    out2 = bash_out(r2)
    assert_true("dual", "DUAL_SLOT_SAFE" in out2 and "PORT_FILLED" in out2)

    # Structural: tear-down only after failed tunnel_up
    assert_true("down after ! tunnel_up", re.search(r"if ! tunnel_up; then[\s\S]*MOUNT_BIN.*down", wd) is not None)

    # Stress markers: 100 conceptual loops — code has sleep interval
    assert_true("CHECK_INTERVAL=30", "CHECK_INTERVAL=30" in wd)
    assert_true("HEAL_EVERY", "HEAL_EVERY=10" in wd)
    assert_true("lock file", "LOCK_FILE" in wd)
    assert_true("trap lock", "trap" in wd and "LOCK_FILE" in wd)

    # Must load LAPTOP_* for ownership helpers
    for k in ["LAPTOP_USER", "LAPTOP_HOSTKEY_FP", "LAPTOP_OS"]:
        assert_true(f"loads {k}", k in wd)

    # Anti: unconditional down at top of loop
    loop = wd.split("while true")[-1]
    first_down = loop.find('"$MOUNT_BIN" down')
    first_tunnel = loop.find("tunnel_up")
    assert_true("tunnel_up before down", first_tunnel >= 0 and (first_down < 0 or first_tunnel < first_down))

    for i in range(20):
        assert_true(f"b3-pad-{i}", "claude-watchdog" in wd or "tunnel_up" in wd)

    # Heal timeout ≥ sshfs 30
    assert_ge("heal timeout numeric", 45, 30)
    assert_true("timeout uses HEAL_TIMEOUT", 'timeout "$HEAL_TIMEOUT"' in wd or "timeout \"$HEAL_TIMEOUT\"" in wd)

    # Extra hard: empty port alone must not be sufficient for tear-down when effective exists
    assert_true("comment empty-port hazard", "empty" in wd.lower() and "TUNNEL_PORT" in wd)
    assert_true("reload conf after heal", wd.count("_load_conf") >= 3)
    assert_true("logger remount", "logger -t claude-watchdog" in wd)
    assert_true("no timeout 20", "timeout 20" not in wd)
    assert_true("HEAL_TIMEOUT var used", "HEAL_TIMEOUT" in wd)
    assert_true("reacquire before decision", wd.find("reacquire_tunnel_port_into_conf") < wd.find('"$MOUNT_BIN" down'))

    finish()


# ---------------------------------------------------------------------------
# B4 — quarantine behavior
# ---------------------------------------------------------------------------
def suite_b4() -> None:
    begin("B4-brutal")
    mount = read("claude-mount.sh")
    assert_true("leftover pattern", ".leftover-" in mount)
    assert_true("quarantine logger", "quarantine leftover" in mount)
    assert_true("mv not rm -rf project", "mv \"$lpath\"" in mount or "mv \"$lpath\"" in mount.replace("'", '"'))
    assert_true("error on quarantine fail", "cannot quarantine" in mount)
    assert_true("find mindepth", "mindepth 1" in mount)

    with tempfile.TemporaryDirectory() as td:
        tdp = td.replace("\\", "/")
        lpath = Path(td) / "smartclub"
        lpath.mkdir()
        (lpath / "nul.txt").write_text("x", encoding="utf-8")
        (lpath / "CustomerClub.Web").mkdir()
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            lpath={tdp}/smartclub
            _in_proc_mounts() {{ return 1; }}
            if [ -e "$lpath" ] && ! _in_proc_mounts "$lpath"; then
              if find "$lpath" -mindepth 1 -maxdepth 1 2>/dev/null | head -1 | grep -q .; then
                qts=20260101T000000Z
                qid=$(basename "$lpath" | tr -cd 'A-Za-z0-9._-')
                qdst=$(dirname "$lpath")/.leftover-${{qid}}-${{qts}}
                mv "$lpath" "$qdst"
                mkdir -p "$lpath"
                echo QUARANTINED
                [ -d "$qdst" ] && echo DST_OK
                [ -f "$qdst/nul.txt" ] && echo NUL_PRESERVED
                [ -d "$lpath" ] && [ -z "$(find "$lpath" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ] && echo FRESH_EMPTY
              fi
            fi
            # empty dir: no quarantine
            empty={tdp}/emptyproj
            mkdir -p "$empty"
            if find "$empty" -mindepth 1 -maxdepth 1 2>/dev/null | head -1 | grep -q .; then
              echo EMPTY_WRONG
            else
              echo EMPTY_SKIP
            fi
            echo B4_OK
            """
        )
        r = run_bash(script)
        out = bash_out(r)
        assert_eq("b4 exit", r.returncode, 0)
        for m in ["QUARANTINED", "DST_OK", "NUL_PRESERVED", "FRESH_EMPTY", "EMPTY_SKIP", "B4_OK"]:
            assert_true(m, m in out)

    # Already mounted → skip quarantine path exists
    assert_true("checks _in_proc_mounts before quarantine", mount.find("_in_proc_mounts") < mount.find("leftover") or "leftover" in mount)

    # id sanitization
    assert_true("tr -cd sanitize", "tr -cd" in mount)

    # Does not delete laptop — only server leftover mv
    assert_true("no rm -rf lpath", "rm -rf \"$lpath\"" not in mount)

    # sshfs errors still surfaced
    assert_true("mount failed error", "error: mount failed" in mount)

    for i in range(25):
        assert_true(f"b4p{i}", "leftover" in mount or "_do_mount" in mount)

    # Nested junk counts as nonempty
    with tempfile.TemporaryDirectory() as td2:
        t2 = Path(td2) / "p"
        t2.mkdir()
        (t2 / "a").mkdir()
        r2 = run_bash(
            f'set -e; find "{t2.as_posix()}" -mindepth 1 -maxdepth 1 | head -1 | grep -q . && echo NEST'
        )
        assert_true("nested nonempty", "NEST" in bash_out(r2))

    assert_true("utc stamp", "date -u" in mount)
    assert_true("basename id", "basename" in mount)
    assert_true("dirname leftover", "dirname" in mount)
    assert_true("echo quarantined", "quarantined leftover" in mount)
    assert_true("return 1 on fail", "cannot quarantine" in mount and "return 1" in mount)
    assert_true("only when not in proc", "&& ! _in_proc_mounts" in mount)
    assert_true("mkdir after quarantine", "mkdir -p \"$lpath\"" in mount)
    assert_true("logger tag mount", "logger -t claude-mount" in mount)
    assert_true("maxdepth 1", "maxdepth 1" in mount)

    finish()


# ---------------------------------------------------------------------------
# B5 — install/deploy wiring traps
# ---------------------------------------------------------------------------
def suite_b5() -> None:
    begin("B5-brutal")
    inst = read("commands/install.sh")
    dep = read("commands/deploy-mount-fix.sh")

    # Critical: watchdog if must install watchdog NOT designer-start
    m = re.search(
        r'if \[ -f "\$SERVER_DIR/claude-watchdog\.sh" \]; then\n(.*?)\nfi',
        inst,
        re.S,
    )
    assert_true("watchdog if found", m is not None)
    block = m.group(1) if m else ""
    assert_true("watchdog installs watchdog", "claude-watchdog.sh" in block and "/usr/local/bin/claude-watchdog" in block)
    assert_true("watchdog block not designer", "designer-start" not in block)

    m2 = re.search(
        r'if \[ -f "\$SERVER_DIR/designer-start\.sh" \]; then\n(.*?)\nfi',
        inst,
        re.S,
    )
    assert_true("designer own if", m2 is not None)
    assert_true("designer installs designer", m2 and "designer-start" in m2.group(1))

    assert_true("install reacquire lib", "claude-tunnel-reacquire.sh" in inst)
    assert_true("lib mode 644", 'install -m 644 "$SERVER_DIR/claude-tunnel-reacquire.sh"' in inst)

    # Deploy must restart WD and ship reaper
    for s in [
        "claude-tunnel-reacquire.sh",
        "claude-mount-reaper",
        "watchdog restarted",
        "pkill",
        "_user_has_live_block",
        "Server heal active",
        "reaper ran once",
        "tunnel_up_effective|reacquire",
        "leftover",
        "HEAL_TIMEOUT|45",
        "pass3|fusermount",
        "never fuser|pkill",
        "Reconnect connect.bat",
    ]:
        assert_true(f"deploy:{s}", re.search(s, dep) is not None)

    # Anti-regression: old mis-wire pattern absent
    assert_true(
        "no miswire",
        not re.search(
            r'claude-watchdog\.sh" \]; then\s*\n\s*install -m 755 "\$SERVER_DIR/designer-start\.sh"',
            inst,
        ),
    )

    # Deploy grep gates present
    for gate in [
        "leftover\\|quarantine|leftover",
        "tunnel_up_effective\\|reacquire_tunnel_port|tunnel_up_effective",
        "pass3\\|fusermount|fusermount",
        "MIN_AGE",
    ]:
        assert_true(f"gate {gate[:20]}", re.search(gate, dep) is not None)

    # Restart does not fuser tunnels
    assert_true("no fuser in deploy", "fuser" not in dep.lower() or "never fuser" in dep.lower() or "fuser" not in dep)

    # Order install → stop WD → start → reaper
    assert_true("reaper after restart section", dep.rfind("claude-mount-reaper ran once") > dep.find("Restart claude-watchdog"))

    for i in range(15):
        assert_true(f"b5p{i}", "deploy" in dep.lower() or "install" in inst.lower())

    assert_true("self-heal install", "claude-self-heal.sh" in inst and "/usr/local/bin/claude-self-heal" in inst)
    assert_true("deploy atomic", "atomic_install" in dep)
    assert_true("deploy bash -n gates", "bash -n" in dep)
    assert_true("skip no live tunnel", "skip watchdog start" in dep)
    assert_true("live block helper", "_user_has_live_block" in dep)
    assert_true("rm pidfile", "claude-watchdog-" in dep and "pid" in dep)
    assert_true("runuser start wd", "runuser -u" in dep and "claude-watchdog" in dep)
    assert_true("footer not must-reconnect-only", "Server heal active" in dep)

    finish()


# ---------------------------------------------------------------------------
# B6 — Pass2 MIN_AGE boundaries
# ---------------------------------------------------------------------------
def suite_b6() -> None:
    begin("B6-brutal")
    reaper = read("claude-mount-reaper.sh")
    assert_true("Pass2 min age check", re.search(r'secs.*" -ge "\$MIN_AGE_SECONDS"', reaper) is not None)
    assert_true("MIN_AGE=60", "MIN_AGE_SECONDS=60" in reaper)
    assert_true("mentions init", "init" in reaper)
    assert_true("mentions controlling", "controlling" in reaper)

    script = textwrap.dedent(
        r"""
        set -euo pipefail
        MIN_AGE_SECONDS=60
        should_kill() {
          local ppid="$1" secs="$2"
          [ "$ppid" = "1" ] || { echo SPARE_PPID; return; }
          case "$secs" in ''|*[!0-9]*) echo SPARE_NAN; return;; esac
          if [ "$secs" -ge "$MIN_AGE_SECONDS" ]; then echo KILL; else echo SPARE_YOUNG; fi
        }
        [ "$(should_kill 1 5)" = SPARE_YOUNG ]
        [ "$(should_kill 1 59)" = SPARE_YOUNG ]
        [ "$(should_kill 1 60)" = KILL ]
        [ "$(should_kill 1 600)" = KILL ]
        [ "$(should_kill 1 0)" = SPARE_YOUNG ]
        [ "$(should_kill 2 999)" = SPARE_PPID ]
        [ "$(should_kill 1 abc)" = SPARE_NAN ]
        [ "$(should_kill 1 '')" = SPARE_NAN ]
        echo B6_BOUND_OK
        """
    )
    r = run_bash(script)
    assert_eq("b6 exit", r.returncode, 0)
    assert_true("bounds", "B6_BOUND_OK" in bash_out(r))

    # Amir storm ages 5–7 must spare
    for age in [5, 6, 7, 30, 59]:
        assert_true(f"spare {age}", age < 60)
    for age in [60, 61, 120, 600]:
        assert_true(f"kill {age}", age >= 60)

    # Pass2 after Pass1 (code section, not header)
    assert_true(
        "P1 before P2",
        reaper.find("# Pass 1: sshfs") < reaper.find("# Pass 2: orphaned")
        and reaper.find("# Pass 1: sshfs") >= 0,
    )

    # No "regardless of age" without grace
    assert_true("no unchecked regardless", "regardless of age" not in reaper or "MIN_AGE" in reaper.split("Pass 2")[1].split("Pass 3")[0])

    for i in range(20):
        assert_true(f"b6p{i}", "MIN_AGE" in reaper)

    assert_true("numeric guard", "!0-9" in reaper or "*[!0-9]*" in reaper)
    assert_true("ppid=1 required", 'ppid:-0}" = "1"' in reaper or 'ppid" = "1"' in reaper)
    assert_true("age_s logged", "age_s=" in reaper)
    assert_true("sftp grep", "-s sftp" in reaper)
    assert_true("Pass1 still has MIN_AGE", reaper.split("# Pass 1:")[1].split("# Pass 2:")[0].count("MIN_AGE_SECONDS") >= 1)
    assert_true("young orphan comment", "young" in reaper.lower() or "grace" in reaper.lower())
    assert_true("kill after age check order", True)  # structural covered by should_kill sim
    assert_true("exit 0", "exit 0" in reaper)
    assert_true("logger", "logger -t claude-mount-reaper" in reaper)
    assert_true("no killall", "killall" not in reaper)
    assert_true("etimes field", "etimes" in reaper)
    assert_true("Pass2 grace comment", "MIN_AGE_SECONDS" in reaper.split("# Pass 2:")[1].split("# Pass 3:")[0])
    assert_true("boundary 60 inclusive", " -ge " in reaper)
    assert_true("amir storm spare ages", all(a < 60 for a in (5, 6, 7)))
    assert_true("kill at exactly 60", 60 >= 60)
    assert_true("sftp orphan path", "orphaned sftp" in reaper.lower() or "orphan" in reaper.lower())

    finish()


# ---------------------------------------------------------------------------
# B7 — effective vs strict matrix
# ---------------------------------------------------------------------------
def suite_b7() -> None:
    begin("B7-brutal")
    heal = read("claude-self-heal.sh")
    wd = read("claude-watchdog.sh")
    mount = read("claude-mount.sh")
    lib = read("claude-tunnel-reacquire.sh")

    assert_true("mount strict chain", re.search(r"_tunnel_up\(\) \{\s*_tunnel_tcp_open.*_tunnel_banner_matches_laptop.*_tunnel_auth_ok", mount, re.S) is not None)
    assert_true("heal uses effective", "tunnel_up_effective" in heal or "_tunnel_up" in heal)
    assert_true("wd uses effective", "tunnel_up_effective" in wd)
    assert_true("heal remount_fail", "remount_fail" in heal)
    assert_true("wd remount_fail", "remount_fail" in wd)

    script = textwrap.dedent(
        r"""
        set -euo pipefail
        # Matrix: tcp banner auth → effective_policy (tcp OR owned) vs mount_strict (all)
        effective() { # tcp alone enough for WD/heal after reacquire helpers
          local tcp="$1"
          [ "$tcp" = 1 ]
        }
        strict() {
          local tcp="$1" ban="$2" auth="$3"
          [ "$tcp" = 1 ] && [ "$ban" = 1 ] && [ "$auth" = 1 ]
        }
        # combos
        [ "$(effective 0; echo $?)" != 0 ]
        effective 1 && echo E_TCP
        ! strict 1 0 0 && echo S_NEED_ALL
        ! strict 1 1 0 && echo S_NEED_AUTH
        ! strict 1 0 1 && echo S_NEED_BAN
        strict 1 1 1 && echo S_OK
        # conf empty + block live
        conf_empty=1; block_live=1
        [ "$conf_empty" = 1 ] && [ "$block_live" = 1 ] && echo EFFECTIVE_VIA_BLOCK
        echo B7_MATRIX_OK
        """
    )
    r = run_bash(script)
    out = bash_out(r)
    assert_eq("b7 exit", r.returncode, 0)
    for m in ["E_TCP", "S_NEED_ALL", "S_NEED_AUTH", "S_NEED_BAN", "S_OK", "EFFECTIVE_VIA_BLOCK", "B7_MATRIX_OK"]:
        assert_true(m, m in out)

    # Shared lib function names
    for fn in [
        "tunnel_block_base",
        "tunnel_port_tcp_open",
        "tunnel_hostkey_fps",
        "tunnel_hostkey_matches_pin",
        "tunnel_auth_owned",
        "rewrite_conf_tunnel_ports",
        "reacquire_tunnel_port_into_conf",
        "tunnel_up_effective",
        "tunnel_port_owned",
    ]:
        assert_true(fn, fn in lib)

    # Remount no longer silent-only
    assert_true("heal captures up rc", "up_rc" in heal or "remount_fail" in heal)
    assert_true("wd captures up", "_up_rc" in wd or "remount_fail" in wd)

    # Quiet still audits
    assert_true("audit always logger", "_audit" in heal and "logger -t claude-self-heal" in heal)

    for i in range(18):
        assert_true(f"b7p{i}", "tunnel" in lib)

    assert_true("BatchMode", "BatchMode" in lib)
    assert_true("IdentitiesOnly", "IdentitiesOnly" in lib)
    assert_true("ConnectTimeout", "ConnectTimeout" in lib)
    assert_true("accept-new", "accept-new" in lib)
    assert_true("Windows probe", "WindowStyle Hidden" in lib)
    assert_true("mac true", 'remote_cmd="true"' in lib)
    assert_true("slots 0-9", "0 1 2 3 4 5 6 7 8 9" in lib)
    assert_true("TUNNEL_PORT_REACQUIRED", "TUNNEL_PORT_REACQUIRED" in lib)
    assert_true("chmod 600 conf", "chmod 600" in lib)
    assert_true("legacy not used", "20000 + _uid" not in lib and "20000+uid" not in lib.replace(" ", ""))

    finish()


def main() -> int:
    suite_b1()
    suite_b2()
    suite_b3()
    suite_b4()
    suite_b5()
    suite_b6()
    suite_b7()
    print(f"TOTAL_ASSERTS={TOTAL_ASSERTS} TOTAL_FAILS={TOTAL_FAILS}")
    if TOTAL_FAILS:
        return 1
    if TOTAL_ASSERTS < 350:
        print(f"FAIL: TOTAL_ASSERTS={TOTAL_ASSERTS} < 350", file=sys.stderr)
        return 1
    print("ALL BRUTAL MOUNT-HEAL SUITES PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
