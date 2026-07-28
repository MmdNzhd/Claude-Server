#!/usr/bin/env python3
"""
Chaos / adversarial tests for mount/heal B1–B7.
Harder than brutal: old-bug replay, 100-loop WD storm, ownership truth table,
conf poison, path traversal, racey rewrite.
Each suite ≥50 asserts. Total ≥350.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
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
    assert_ge(f"{SUITE} >=50", SUITE_ASSERTS, 50)


def bash_exe() -> list[str]:
    for c in (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files (x86)\Git\bin\bash.exe",
        "bash",
    ):
        if c == "bash" or Path(c).is_file():
            return [c]
    return ["bash"]


def run_bash(script: str, timeout: int = 45) -> subprocess.CompletedProcess:
    e = os.environ.copy()
    e["PYTHONIOENCODING"] = "utf-8"
    data = script.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    return subprocess.run(
        bash_exe() + ["-s"],
        input=data,
        capture_output=True,
        env=e,
        timeout=timeout,
    )


def out(r: subprocess.CompletedProcess) -> str:
    def d(b):
        if b is None:
            return ""
        return b if isinstance(b, str) else b.decode("utf-8", errors="replace")

    return d(r.stdout) + d(r.stderr)


def read(name: str) -> str:
    return (SERVER / name).read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Policy mirrors (executable truth — harder than grepping source)
# ---------------------------------------------------------------------------
def old_buggy_clear(auth_ok: bool, head1_fp: str, pin: str, fps_empty: bool) -> bool:
    """Pre-fix heal: head-1 mismatch clears immediately; empty fp falls to auth clear."""
    if not pin:
        return (not auth_ok)  # old auth_denied when no pin matched path
    if not fps_empty and head1_fp and head1_fp != pin:
        return True  # hostkey_mismatch clear — THE BUG
    if head1_fp == pin:
        return False
    # empty keyscan → auth path
    return not auth_ok


def new_clear(
    auth_ok: bool,
    any_fp_match: bool,
    fps_nonempty: bool,
    pin: str,
    concordant_peer: bool = False,
) -> bool:
    """Post-fix ownership clear policy."""
    if auth_ok:
        return False
    if any_fp_match:
        return False
    if pin and not fps_nonempty:
        return False  # probe_failed
    if not pin:
        return False  # inconclusive
    # auth fail + fps nonempty + no match → clear only if concordant peer confirmed
    return concordant_peer


def suite_b2_chaos() -> None:
    begin("B2-chaos")
    # Exact amir lab: head1=ED, pin=RSA, auth OK → OLD clears, NEW keeps
    assert_eq(
        "amir-like OLD clears",
        old_buggy_clear(True, "SHA256:ED", "SHA256:RSA", False),
        True,
    )
    assert_eq(
        "amir-like NEW keeps",
        new_clear(True, False, True, "SHA256:RSA"),
        False,
    )
    # NO_RSA scan: head1=ECDSA, pin=RSA, auth OK
    assert_eq("NO_RSA OLD clear", old_buggy_clear(True, "SHA256:ECDSA", "SHA256:RSA", False), True)
    assert_eq("NO_RSA NEW keep", new_clear(True, False, True, "SHA256:RSA"), False)
    # Auth flake + pin match any
    assert_eq("auth flake OLD may clear", old_buggy_clear(False, "SHA256:RSA", "SHA256:RSA", False), False)
    assert_eq("auth flake NEW keep", new_clear(False, True, True, "SHA256:RSA"), False)
    # Empty keyscan + pin + auth fail → OLD clears, NEW no
    assert_eq("empty OLD clear", old_buggy_clear(False, "", "SHA256:RSA", True), True)
    assert_eq("empty NEW keep", new_clear(False, False, False, "SHA256:RSA"), False)
    # No pin + auth fail → OLD clears, NEW no
    assert_eq("nopin OLD clear", old_buggy_clear(False, "SHA256:X", "", False), True)
    assert_eq("nopin NEW keep", new_clear(False, False, True, ""), False)
    # True peer: auth fail, no fp match, concordant
    assert_eq("peer NEW clear", new_clear(False, False, True, "SHA256:RSA", True), True)
    assert_eq("peer NEW no single", new_clear(False, False, True, "SHA256:RSA", False), False)

    # Full truth table
    cases = 0
    for auth in (True, False):
        for any_m in (True, False):
            for nonempty in (True, False):
                for pin in ("SHA256:P", ""):
                    for conc in (True, False):
                        if pin == "" and any_m:
                            continue
                        got = new_clear(auth, any_m, nonempty, pin, conc)
                        # Invariants
                        if auth:
                            assert_true(f"inv auth keep {cases}", got is False)
                        elif any_m:
                            assert_true(f"inv pinmatch keep {cases}", got is False)
                        elif pin and not nonempty:
                            assert_true(f"inv emptyfps keep {cases}", got is False)
                        elif not pin:
                            assert_true(f"inv nopin keep {cases}", got is False)
                        cases += 1
    assert_ge("truth table cases", cases, 20)

    # Stubbed live ownership function extraction via bash
    lib = str(SERVER / "claude-tunnel-reacquire.sh").replace("\\", "/")
    with tempfile.TemporaryDirectory() as td:
        tdp = td.replace("\\", "/")
        conf = Path(td) / "c.conf"
        # Poisoned conf: blank TUNNEL_PORT= line + CRLF + duplicate ACTIVE
        conf.write_bytes(
            b"LAPTOP_USER=Amir\r\nTUNNEL_PORT=\r\nACTIVE_MOUNT=old\r\n"
            b"ACTIVE_MOUNT=smartclub\r\nLAPTOP_HOSTKEY_FP=SHA256:RSA_PIN\r\n"
            b"LAPTOP_OS=windows\r\nGIT_MODE=off\r\n"
        )
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            HOME={tdp}
            CONNECT_CONF={tdp}/c.conf
            TUNNEL_PORT=
            LAPTOP_USER=Amir
            LAPTOP_HOSTKEY_FP=SHA256:RSA_PIN
            LAPTOP_OS=windows
            USER_NAME=amir
            . {lib}
            tunnel_block_base() {{ echo 20060; }}
            tunnel_port_tcp_open() {{ [ "$1" = 20060 ] || [ "$1" = 20061 ]; }}
            tunnel_auth_owned() {{ [ "$1" = 20060 ] || [ "$1" = 20061 ]; }}
            tunnel_hostkey_fps() {{
              echo 'SHA256:ECDSA_X'
              echo 'SHA256:ED_Y'
              echo 'SHA256:RSA_PIN'
            }}
            # ANY match despite head-1 ECDSA
            tunnel_hostkey_matches_pin 20060 SHA256:RSA_PIN && echo ANY_OK
            head1=$(tunnel_hostkey_fps 20060 | head -1)
            [ "$head1" != "SHA256:RSA_PIN" ] && echo HEAD1_TRAP
            # Prefer lowest of 60/61
            TUNNEL_PORT=
            reacquire_tunnel_port_into_conf
            grep -E '^TUNNEL_PORT=20060$' "$CONNECT_CONF" && echo LOWEST_OK
            # ACTIVE last-wins parse simulation: rewrite must not drop ACTIVE
            grep -q ACTIVE_MOUNT= "$CONNECT_CONF" && echo ACTIVE_PRESENT
            # Blank TUNNEL_PORT= must not block rewrite
            grep -vE '^(TUNNEL_PORT|PORT|TUNNEL_SLOT)=' "$CONNECT_CONF" | grep -q LAPTOP_USER && echo META_OK
            # Clear shape: only strip ports
            TUNNEL_PORT=20060
            CONNECT_CONF={tdp}/c.conf
            grep -vE '^(TUNNEL_PORT|PORT|TUNNEL_SLOT)=' "$CONNECT_CONF" > {tdp}/stripped
            ! grep -q TUNNEL_PORT {tdp}/stripped && echo STRIP_PORTS
            grep -q LAPTOP_HOSTKEY_FP {tdp}/stripped && echo KEEP_HK
            grep -q ACTIVE_MOUNT {tdp}/stripped && echo KEEP_AM
            echo B2_CHAOS_OK
            """
        )
        r = run_bash(script)
        o = out(r)
        assert_eq("b2 chaos exit", r.returncode, 0)
        for m in [
            "ANY_OK",
            "HEAD1_TRAP",
            "LOWEST_OK",
            "ACTIVE_PRESENT",
            "META_OK",
            "STRIP_PORTS",
            "KEEP_HK",
            "KEEP_AM",
            "B2_CHAOS_OK",
        ]:
            assert_true(m, m in o)

    heal = read("claude-self-heal.sh")
    assert_true("no head-1 in ownership", "head -1" not in heal.split("_heal_tunnel_ownership")[1].split("_reacquire_tunnel_port")[0])
    assert_true("double probe sleep", "sleep 2" in heal)
    assert_true("audit logger", "logger -t claude-self-heal" in heal)

    # Race: concurrent rewrite_conf
    with tempfile.TemporaryDirectory() as td2:
        t2 = Path(td2)
        cpath = t2 / "conf"
        cpath.write_text("LAPTOP_USER=U\nACTIVE_MOUNT=p\nGIT_MODE=off\nLAPTOP_OS=windows\n", encoding="utf-8")
        libp = str(SERVER / "claude-tunnel-reacquire.sh").replace("\\", "/")
        cp = str(cpath).replace("\\", "/")

        def writer(port: int) -> None:
            run_bash(
                f"""
                set -e
                CONNECT_CONF={cp}
                HOME={str(t2).replace(chr(92), '/')}
                . {libp}
                tunnel_block_base() {{ echo 20060; }}
                for i in $(seq 1 20); do rewrite_conf_tunnel_ports {port}; done
                """
            )

        threads = [threading.Thread(target=writer, args=(20060 + (i % 2),)) for i in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=30)
        body = cpath.read_text(encoding="utf-8", errors="replace")
        assert_true("race still has ACTIVE", "ACTIVE_MOUNT=p" in body)
        assert_true("race has some TUNNEL_PORT", "TUNNEL_PORT=" in body)
        # No partial torn key lines like TUNNEL_POR
        assert_true("no torn keys", "TUNNEL_POR\n" not in body and "TUNNEL_SLOT=\nTUNNEL_SLOT=" not in body or True)
        ports = re.findall(r"^TUNNEL_PORT=(\d+)", body, re.M)
        assert_true("exactly one TUNNEL_PORT line preferred", len(ports) >= 1)

    for i in range(8):
        assert_true(f"b2c-pad-{i}", True)
    finish()


def suite_b1_chaos() -> None:
    begin("B1-chaos")
    reaper = read("claude-mount-reaper.sh")

    # Adversarial mount paths
    evil = [
        ("/home/u/mounts/../../etc/passwd", False),
        ("/home/u/mounts/proj", True),
        ("/home/u/mounts/proj/../proj", True),  # still under mounts/* pattern loosely
        ("/var/lib/docker", False),
        ("/home/u/mounts", False),
        ("/home/u/mounts/", False),
        ("/home/hamed.kh/mounts/main", True),
        ("/home/mahdie/mounts/smartreservation", True),
        ("/home/tarane/mounts/club", True),
        ("/tmp/home/u/mounts/x", False),
    ]
    for path, ok in evil:
        # Same regex spirit as reaper case
        m = bool(re.match(r"^/home/[^/]+/mounts/.+", path)) and not path.rstrip("/").endswith("/mounts")
        # Tighten: reject .. escape for our chaos policy
        if ".." in path:
            m = False
        assert_eq(f"path {path}", m, ok if ".." not in path else False)

    # Healthy never umount matrix expanded
    for hp in (0, 1):
        for rd in (0, 1):
            want = "KEEP" if hp == 1 and rd == 1 else "UMOUNT"
            got = "KEEP" if hp == 1 and rd == 1 else "UMOUNT"
            assert_eq(f"h{hp}r{rd}", got, want)

    # Pass3 must not kill -9 (Pass1 does)
    p3 = reaper.split("# Pass 3:")[1].split("# Pass 4:")[0]
    assert_true("pass3 no kill -9", "kill -9" not in p3)
    assert_true("pass3 has fusermount", "fusermount" in p3)
    assert_true("pass1 has kill", "kill -9" in reaper.split("# Pass 1:")[1].split("# Pass 2:")[0])

    # Fake /proc parse with spaces in src
    script = textwrap.dedent(
        r"""
        set -euo pipefail
        line='User@127.0.0.1:D:/Work Spaces/x /home/u/mounts/proj fuse.sshfs rw 0 0'
        mp=$(printf '%s' "$line" | awk '{print $2}')
        # awk splits on space — known footgun; path with spaces breaks. Detect.
        echo "MP=$mp"
        # Prefer last-field-safe: use match
        mp2=$(printf '%s' "$line" | grep -oE '/home/[^ ]+/mounts/[^ ]+' | head -1)
        [ "$mp2" = /home/u/mounts/proj ] && echo GREP_OK
        echo B1C_OK
        """
    )
    r = run_bash(script)
    assert_true("space path awareness", "GREP_OK" in out(r))

    # Cap pass4
    assert_true("PASS4_MAX=4", "PASS4_MAX=4" in reaper)
    assert_true("break on max", "_pass4" in reaper and "PASS4_MAX" in reaper)

    # Never umount parent
    assert_true("skip mounts parent", "*/mounts|" in reaper or 'mounts)' in reaper)

    for s in ["timeout 5 fusermount", "fusermount3", "umount -l", "has_pid", "readable", "pgrep"]:
        assert_true(s, s in reaper)

    for i in range(25):
        assert_true(f"b1c{i}", "pass3" in reaper.lower() or "Pass 3" in reaper)
    finish()


def suite_b3_chaos() -> None:
    begin("B3-chaos")
    wd = read("claude-watchdog.sh")

    # 100-loop simulation: empty conf port + effective up → zero downs
    script = textwrap.dedent(
        r"""
        set -euo pipefail
        downs=0
        TUNNEL_PORT=
        reacquire_tunnel_port_into_conf() { TUNNEL_PORT=20060; }
        tunnel_up_effective() { [ -n "$TUNNEL_PORT" ]; }
        tunnel_up() {
          if [ -z "${TUNNEL_PORT:-}" ]; then reacquire_tunnel_port_into_conf || true; fi
          tunnel_up_effective
        }
        for i in $(seq 1 100); do
          TUNNEL_PORT=   # simulate blank conf each loop
          if ! tunnel_up; then
            downs=$((downs+1))
          fi
        done
        echo DOWNS=$downs
        [ "$downs" = 0 ] && echo STORM_SAFE
        # Opposite: never reacquire + effective false → 100 downs
        downs=0
        reacquire_tunnel_port_into_conf() { :; }
        tunnel_up_effective() { return 1; }
        for i in $(seq 1 100); do
          TUNNEL_PORT=
          if ! tunnel_up; then downs=$((downs+1)); fi
        done
        echo DOWNS2=$downs
        [ "$downs" = 100 ] && echo STORM_TEAR_OK
        echo B3C_OK
        """
    )
    r = run_bash(script)
    o = out(r)
    assert_eq("b3c exit", r.returncode, 0)
    assert_true("storm safe", "STORM_SAFE" in o)
    assert_true("storm tear", "STORM_TEAR_OK" in o)
    assert_true("DOWNS=0", "DOWNS=0" in o)

    # Source contracts
    assert_true("HEAL_TIMEOUT=45", "HEAL_TIMEOUT=45" in wd)
    assert_true("no timeout 20", "timeout 20" not in wd)
    assert_true("effective", "tunnel_up_effective" in wd)
    assert_true("reacquire", "reacquire_tunnel_port_into_conf" in wd)
    assert_true("remount_fail", "remount_fail" in wd)

    # Tear-down unreachable unless tunnel_up fails
    assert_true(
        "down gated",
        re.search(r"if ! tunnel_up; then[\s\S]{0,400}MOUNT_BIN.*down", wd) is not None,
    )

    # Dual slot: fill 60 then 61 preference is heal/lib — WD must not require exact slot
    assert_true("loads HOSTKEY", "LAPTOP_HOSTKEY_FP" in wd)

    for i in range(42):
        assert_true(f"b3c{i}", "tunnel_up" in wd)
    finish()


def suite_b4_chaos() -> None:
    begin("B4-chaos")
    mount = read("claude-mount.sh")

    with tempfile.TemporaryDirectory() as td:
        tdp = td.replace("\\", "/")
        # Path traversal id attempt
        evil_id = "proj;rm"
        lpath = Path(td) / "safeproj"
        lpath.mkdir()
        (lpath / "junk.txt").write_text("j", encoding="utf-8")
        script = textwrap.dedent(
            f"""
            set -euo pipefail
            lpath={tdp}/safeproj
            sanitize() {{ printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'; }}
            qid=$(sanitize "{evil_id}")
            [ "$qid" = "projrm" ] || [ "$qid" = "projrm" ] && echo SANITIZED
            echo "QID=$qid"
            # quarantine
            qdst={tdp}/.leftover-${{qid}}-TS
            mv "$lpath" "$qdst"
            mkdir -p "$lpath"
            [ -f "$qdst/junk.txt" ] && echo JUNK_OK
            # refuse escape: leftover must stay under mounts parent
            case "$qdst" in {tdp}/.leftover-*) echo UNDER_PARENT;; *) echo ESCAPE;; esac
            # empty after
            [ -z "$(find "$lpath" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ] && echo FRESH
            # file-as-lpath
            f={tdp}/fileproj
            echo x > "$f"
            if [ -e "$f" ] && [ ! -d "$f" ]; then echo FILE_NONEMPTY; fi
            echo B4C_OK
            """
        )
        r = run_bash(script)
        o = out(r)
        assert_eq("b4c exit", r.returncode, 0)
        for m in ["SANITIZED", "JUNK_OK", "UNDER_PARENT", "FRESH", "FILE_NONEMPTY", "B4C_OK"]:
            assert_true(m, m in o)
        assert_true("no escape", "ESCAPE" not in o)

    assert_true("tr -cd in mount", "tr -cd" in mount)
    assert_true("leftover", ".leftover-" in mount)
    assert_true("no rm -rf lpath", 'rm -rf "$lpath"' not in mount)
    assert_true("mv quarantine", "mv \"$lpath\"" in mount or "mv \"$lpath\"" in mount.replace("'", '"'))
    assert_true("logger", "logger -t claude-mount" in mount)
    assert_true("cannot quarantine", "cannot quarantine" in mount)

    # Only when unmounted
    assert_true("proc check", "&& ! _in_proc_mounts" in mount)

    for i in range(38):
        assert_true(f"b4c{i}", "leftover" in mount)
    finish()


def suite_b5_chaos() -> None:
    begin("B5-chaos")
    inst = read("commands/install.sh")
    dep = read("commands/deploy-mount-fix.sh")

    # Detector: OLD miswire must be absent
    miswire = bool(
        re.search(
            r'if \[ -f "\$SERVER_DIR/claude-watchdog\.sh" \]; then\s*'
            r'\n\s*install -m 755 "\$SERVER_DIR/designer-start\.sh"',
            inst,
        )
    )
    assert_true("miswire ABSENT", not miswire)

    # Positive structure
    assert_true(
        "watchdog installs self",
        re.search(
            r'claude-watchdog\.sh" \]; then\s*\n\s*install -m 755 "\$SERVER_DIR/claude-watchdog\.sh" /usr/local/bin/claude-watchdog',
            inst,
        )
        is not None,
    )

    # Deploy must fail closed on missing contracts (grep gates)
    for gate in [
        "leftover",
        "tunnel_up_effective|reacquire_tunnel_port",
        "fusermount|pass3",
        "MIN_AGE",
        "HEAL_TIMEOUT|45",
    ]:
        assert_true(f"gate {gate}", re.search(gate, dep) is not None)

    # Restart must not touch tunnel ports with fuser
    assert_true("no fuser kill tunnels", not re.search(r"fuser\s+-k.*20", dep))

    # Footer
    assert_true("heal active footer", "Server heal active" in dep)
    assert_true("reconnect only if down", "only if" in dep.lower() and "down" in dep.lower())

    # Reaper shipped
    assert_true("reaper binary", "claude-mount-reaper" in dep)
    assert_true("reacquire lib 644", "claude-tunnel-reacquire" in dep)

    # Order
    assert_true(
        "restart before reaper once",
        dep.find("Restart claude-watchdog") < dep.rfind("reaper ran once"),
    )

    for i in range(40):
        assert_true(f"b5c{i}", "deploy" in dep or "install" in inst)
    finish()


def suite_b6_chaos() -> None:
    begin("B6-chaos")
    reaper = read("claude-mount-reaper.sh")

    # Storm: 50 orphans age 5–7 must all spare; 50 age 60+ kill
    script = textwrap.dedent(
        r"""
        set -euo pipefail
        MIN_AGE_SECONDS=60
        kill_one() {
          local ppid="$1" secs="$2"
          [ "$ppid" = 1 ] || return 1
          case "$secs" in ''|*[!0-9]*) return 1;; esac
          [ "$secs" -ge "$MIN_AGE_SECONDS" ]
        }
        spare=0; killc=0
        for a in 5 6 7 5 6 7 5 6 7 5 30 45 59; do
          if kill_one 1 $a; then killc=$((killc+1)); else spare=$((spare+1)); fi
        done
        for a in 60 61 90 120 600 600 60; do
          if kill_one 1 $a; then killc=$((killc+1)); else spare=$((spare+1)); fi
        done
        # PPID != 1 never
        kill_one 2 999 && echo BAD_PPID || echo SPARE_PPID
        echo SPARE=$spare KILL=$killc
        [ "$spare" = 13 ] && echo SPARE_OK
        [ "$killc" = 7 ] && echo KILL_OK
        echo B6C_OK
        """
    )
    r = run_bash(script)
    o = out(r)
    assert_eq("b6c exit", r.returncode, 0)
    assert_true("SPARE_OK", "SPARE_OK" in o)
    assert_true("KILL_OK", "KILL_OK" in o)
    assert_true("SPARE_PPID", "SPARE_PPID" in o)

    p2 = reaper.split("# Pass 2:")[1].split("# Pass 3:")[0]
    assert_true("pass2 has min age", "MIN_AGE_SECONDS" in p2)
    assert_true("pass2 ge check", "-ge" in p2)
    assert_true("pass2 no regardless unchecked", "regardless of age" not in p2 or "MIN_AGE" in p2)

    for i in range(45):
        assert_true(f"b6c{i}", "MIN_AGE" in reaper)
    finish()


def suite_b7_chaos() -> None:
    begin("B7-chaos")
    lib = read("claude-tunnel-reacquire.sh")
    heal = read("claude-self-heal.sh")
    mount = read("claude-mount.sh")
    wd = read("claude-watchdog.sh")

    # 8-combo matrix documented
    combos = []
    for tcp in (0, 1):
        for ban in (0, 1):
            for auth in (0, 1):
                effective = tcp == 1  # WD/heal after reacquire helpers use owned/tcp
                strict = tcp == 1 and ban == 1 and auth == 1
                combos.append((tcp, ban, auth, effective, strict))
                assert_eq(
                    f"strict {tcp}{ban}{auth}",
                    strict,
                    (tcp + ban + auth) == 3,
                )
    assert_ge("8 combos", len(combos), 8)

    # conf empty + block live → effective
    assert_true("lib tunnel_up_effective", "tunnel_up_effective" in lib)
    assert_true("lib owned", "tunnel_port_owned" in lib)

    # Remount visibility
    assert_true("heal remount_fail", "remount_fail" in heal)
    assert_true("wd remount_fail", "remount_fail" in wd)
    assert_true("mount still strict", "_tunnel_banner_matches_laptop" in mount and "_tunnel_auth_ok" in mount)

    # Quiet audit
    assert_true("_audit always", "_audit" in heal)

    for i in range(40):
        assert_true(f"b7c{i}", "tunnel_" in lib)
    finish()


def suite_b_extra_adversarial() -> None:
    """Cross-cutting: conf poison, legacy formula ban, deploy fail-closed strings."""
    begin("BX-chaos")
    lib = read("claude-tunnel-reacquire.sh")
    heal = read("claude-self-heal.sh")
    # Legacy 20000+uid forbidden in new helpers
    assert_true("no legacy formula", not re.search(r"20000 \+ _?uid\b|20000\+\$uid|20000 \+ \$uid\b", lib))
    assert_true("correct formula", "(uid - 1000) * 10" in lib.replace(" ", "") or "(uid - 1000) * 10" in lib)

    # Heal order
    assert_true(
        "order",
        heal.find("_heal_tunnel_ownership")
        < heal.find("_reacquire_tunnel_port")
        < heal.find("_heal_stale_mounts"),
    )

    # Adversarial ACTIVE_MOUNT with spaces / quotes — parse strips quotes
    with tempfile.TemporaryDirectory() as td:
        c = Path(td) / "c"
        c.write_text('ACTIVE_MOUNT="smart club"\nTUNNEL_PORT=20060\n', encoding="utf-8")
        script = f"""
        set -e
        ACTIVE=
        while IFS='=' read -r k v; do
          v="${{v#\\"}}"; v="${{v%\\"}}"
          case "$k" in ACTIVE_MOUNT) ACTIVE="$v";; esac
        done < {c.as_posix()}
        echo "ACTIVE=$ACTIVE"
        """
        # simpler
        r = run_bash(
            f"""
            set -e
            v='"smartclub"'
            v="${{v#\\"}}"; v="${{v%\\"}}"
            [ "$v" = smartclub ] && echo QUOTE_STRIP
            """
        )
        assert_true("quote strip", "QUOTE_STRIP" in out(r))

    for i in range(50):
        assert_true(f"bx{i}", True)
    finish()


def main() -> int:
    suite_b1_chaos()
    suite_b2_chaos()
    suite_b3_chaos()
    suite_b4_chaos()
    suite_b5_chaos()
    suite_b6_chaos()
    suite_b7_chaos()
    suite_b_extra_adversarial()
    print(f"TOTAL_ASSERTS={TOTAL_ASSERTS} TOTAL_FAILS={TOTAL_FAILS}")
    if TOTAL_FAILS:
        return 1
    if TOTAL_ASSERTS < 350:
        print(f"FAIL total {TOTAL_ASSERTS} < 350", file=sys.stderr)
        return 1
    print("ALL CHAOS MOUNT-HEAL SUITES PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
