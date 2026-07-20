# HARD TEST Agent E — Mac client scripts

**Date:** 2026-07-20  
**Project:** `-p claude-code-server`  
**Deploy:** none  
**Verdict:** **HARD FAIL** (static assertions failed)

---

## Shell test

### Command 1 (requested)

```bash
laptop-exec run -p claude-code-server -- cmd /c "bash D:/Smart/Claude-Code-Server/scripts/client/tests/test-mac-laptop-ssh.sh"
```

**Result:** BLOCKED / failed  
**Exit:** 127  
**Detail:** `cmd /c bash` resolved to WSL/`C:\WINDOWS\system32\bash.exe`. WSL bash could not open the Windows path:

`/bin/bash: D:/Smart/Claude-Code-Server/scripts/client/tests/test-mac-laptop-ssh.sh: No such file or directory`

(Also printed WSL mirrored-networking localhostForwarding notice.)

### Fallback: Git Bash

```powershell
& 'C:\Program Files\Git\bin\bash.exe' 'D:/Smart/Claude-Code-Server/scripts/client/tests/test-mac-laptop-ssh.sh'
```

**Result:** `OK test-mac-laptop-ssh.sh` (exit 0)

### Fallback: WSL Ubuntu

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'bash /mnt/d/Smart/Claude-Code-Server/scripts/client/tests/test-mac-laptop-ssh.sh'
```

**Result:** `OK test-mac-laptop-ssh.sh` (EXIT=0)

### Note

`test-mac-laptop-ssh.sh` is an older static grep suite (self-heal / reverse-SSH helpers). It does **not** cover the five HARD assertions below. Passing the shell test does **not** override static HARD FAIL.

---

## Static HARD assertions (rg / read)

Each FAIL is listed. Overall static result: **HARD FAIL**.

### 1. `recover_mounts_if_needed` must NOT nest `sshx ... sshx` / bare server-side `sshx` in recover fallback

| Status | **FAIL** |
|---|---|
| File | `scripts/client/git-mode.sh` |
| Function | `recover_mounts_if_needed` (~L1004) |
| Evidence | |

```text
timeout 30 sshx "$CM recover-one '$id' 2>/dev/null || timeout 30 sshx "$CM recover-if-needed '$id' 2>/dev/null || timeout 30 sshx "$CM recover" 2>/dev/null || true
```

Broken quoting: multiple `sshx` chained inside one outer `sshx` argument / `||` chain (nested `sshx ... sshx`). Recover fallback is malformed.

Healthy early path (`recover-if-needed` when mount healthy + git off) uses a single `sshx` and is OK; the stale-mount fallback is the violation.

---

### 2. Tunnel wait must be `seq 1 12` (or equivalent ≥12), NOT `seq 1 4`

| Status | **FAIL** |
|---|---|
| File | `scripts/client/git-mode.sh` |

| Function | Line | Loop | Notes |
|---|---|---|---|
| `wait_for_tunnel_up` | ~887 | `for i in $(seq 1 4)` | Only 4 attempts |
| `poll_tunnel_with_progress` | ~905 | `for i in $(seq 1 4)` | Progress text says `%d/12` and has `i -ge 12` break, but loop never reaches 12 |

Required: `seq 1 12` or equivalent ≥12 iterations.

---

### 3. PushConf must NOT have `|| true` that masks failure

| Status | **FAIL** |
|---|---|
| File | `scripts/client/git-mode.sh` |
| Function | `push_server_connect_conf` (~L131) |
| Evidence | |

```bash
push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null || true)"
push_ec=$?
```

`|| true` forces command-substitution success, so `push_ec` is always `0` and the subsequent fail branch is dead. PushConf failures are masked.

(Other `|| true` elsewhere in the file are out of scope; this is the PushConf mask.)

---

### 4. `CLEAR_MOUNT` must include `Reason=`

| Status | **FAIL** |
|---|---|
| File | `scripts/client/git-mode.sh` |
| Function | `clear_session_mount` (~L329) |
| Evidence | |

```bash
connect_log "CLEAR_MOUNT project=$project_id skip_editor=$skip_editor editor=$editor_cmd path=$remote_path" 'INFO'
```

No `Reason=` field. (Mac connect has `RECOVERY_SKIP_CLEAR_MOUNT reason=editor_open` and session disconnect `reason=user_quit`, but the CLEAR_MOUNT log line itself lacks `Reason=`.)

---

### 5. Abort paths must pass `--clear` / clear active mount

| Status | **FAIL** |
|---|---|
| File | `scripts/client/mac/connect.sh` |

Abort / quit-from-failure paths set `ACTIVE_MOUNT_ID=""` then call `push_server_connect_conf` **without** `--clear`:

| Approx lines | Trigger |
|---|---|
| ~652–654 | Tunnel did not come up → user Q |
| ~695–697 | Laptop SSH auth fail → user Q |
| ~760–762 | Mount fail → user Q |

With empty prefer/active and **no** `--clear`, `push_server_connect_conf` **preserves** existing server `ACTIVE_MOUNT` (by design). Abort therefore does **not** clear active mount.

Contrast: `clear_session_mount` correctly ends with `push_server_connect_conf --clear` (disconnect / recovery-clear paths ~595, ~1039, ~1053). Abort Q paths do not use that.

---

## Summary

| Check | Result |
|---|---|
| Shell test (requested `cmd /c bash`) | Blocked (path/WSL) |
| Shell test (Git Bash) | OK (suite does not cover HARD asserts) |
| Shell test (WSL `/mnt/d/...`) | OK (same) |
| Static 1 nested sshx recover | **FAIL** |
| Static 2 tunnel wait ≥12 | **FAIL** |
| Static 3 PushConf `\|\| true` | **FAIL** |
| Static 4 CLEAR_MOUNT Reason= | **FAIL** |
| Static 5 abort `--clear` | **FAIL** |

**HARD FAIL** — static checks fail even though alternate shell runners can execute `test-mac-laptop-ssh.sh` successfully.
