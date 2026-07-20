# FIX-W2 - Mac laptop-exec P0 parity (git-mode.sh + mac/connect.sh)

Agent W2. Scope: `scripts/client/git-mode.sh`, `scripts/client/mac/connect.sh`.
No deploy. No commit. Verified with `laptop-exec rg -p claude-code-server` after edits.

## Summary

| # | Bug id | Status |
|---|---|---|
| 1 | mac-recover-quote-mangle | FIXED |
| 2 | mac-tunnel-wait-4-vs-win-12 | FIXED |
| 3 | Mac banner_miss softfail (budget + ensure) | FIXED |
| 4 | mac-abort-no-clear-active-mount | FIXED |
| 5 | mac-post-recover-pid-only | FIXED |
| 6 | mac-fallthrough-skips-recovery-policy | FIXED |
| 7 | PushConf `|| true` masks ssh failure | FIXED |

---

## 1. mac-recover-quote-mangle (P0)

**File:** `scripts/client/git-mode.sh` - `recover_mounts_if_needed`

### BEFORE (broken nested quotes / nested sshx)

```bash
timeout 30 sshx "$CM recover-one '$id' 2>/dev/null || timeout 30 sshx "$CM recover-if-needed '$id' 2>/dev/null || timeout 30 sshx "$CM recover" 2>/dev/null || true
```

### AFTER (Win parity - one sshx, one remote string) ~L1017

```bash
if ! sshx "timeout 30 $CM recover-one '$id' 2>/dev/null || timeout 30 $CM recover-if-needed '$id' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true"; then
```

rg: `timeout 30 sshx` absent in scripts/client/git-mode.sh (exit 1).
rg: `sshx "timeout 30 $CM recover-one` present once.

---

## 2. mac-tunnel-wait-4-vs-win-12 (P0)

**File:** `scripts/client/git-mode.sh` - `wait_for_tunnel_up`, `poll_tunnel_with_progress`

### BEFORE

```bash
for i in $(seq 1 4); do   # wait ~887
for i in $(seq 1 4); do   # poll ~905
```

### AFTER

```bash
# wait_for_tunnel_up ~L877
for i in $(seq 1 12); do
# poll_tunnel_with_progress ~L907
for i in $(seq 1 12); do
```

rg: `seq 1 12` x2; `seq 1 4` absent in scripts/client/git-mode.sh (exit 1).

---

## 3. Mac banner_miss softfail

**File:** `scripts/client/git-mode.sh`

### 3a TUNNEL_SYNC BEFORE

Logged `banner_miss_tcp_open` and reset fail counts; never budgeted SoftFail toward DROP.

### 3a TUNNEL_SYNC AFTER ~L836-L847

```bash
_TUNNEL_SOFT_FAIL_COUNT=$(( ${_TUNNEL_SOFT_FAIL_COUNT:-0} + 1 ))
connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/6 ... reason=banner_miss_tcp_open"
if [ "$_TUNNEL_SOFT_FAIL_COUNT" -ge 6 ]; then
    connect_log "TUNNEL_DROP ... reason=banner_miss_tcp_open_budget count=$_TUNNEL_SOFT_FAIL_COUNT"
    return 1
fi
return 0
```

### 3b ensure_session_tunnel BEFORE

```bash
if tunnel_port_tcp_open "$PORT"; then
    connect_log "... reason=banner_miss_tcp_open"
    TUNNEL_REUSED=1
    return 0   # BUG: succeed on banner_miss alone
fi
```

### 3b ensure_session_tunnel AFTER ~L1129-L1134

```bash
# Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
if tunnel_port_tcp_open "$PORT"; then
    connect_log "ENSURE_TUNNEL soft_fail ... reason=banner_miss_tcp_open action=reseed"
    # Fall through to kill stale bg + reseed below.
fi
```

rg: `banner_miss_tcp_open_budget` + `action=reseed` present.

---

## 4. mac-abort-no-clear-active-mount

**File:** `scripts/client/mac/connect.sh`

### BEFORE

```bash
ACTIVE_MOUNT_ID=""
push_server_connect_conf    # without --clear
```

### AFTER (3 abort quit sites: L676, L720, L785)

```bash
ACTIVE_MOUNT_ID=""
push_server_connect_conf --clear
```

---

## 5. mac-post-recover-pid-only

**File:** `scripts/client/mac/connect.sh`

### BEFORE

```bash
recover_mounts_if_needed ...
if ! _tunnel_alive "$bg_pid"; then   # PID-only
```

### AFTER ~L691-L697 (Win Test-TunnelUp parity)

```bash
# Win Test-TunnelUp parity - banner/TCP, not PID-only.
if ! tunnel_up; then
    printf '      -> tunnel dropped during recover, restarting...\n'
    ...
fi
```

---

## 6. mac-fallthrough-skips-recovery-policy

**File:** `scripts/client/mac/connect.sh`

### BEFORE

```bash
elif tunnel_down; then
    _action="r"
    continue   # BUG: next loop resets _action; skips preserve/clear
```

### AFTER ~L1012-L1019 (set action=r BEFORE handler)

```bash
# Win parity: set action=r before handler so preserve/clear recovery runs
if [ -z "$_action" ] && { [ "$_tunnel_sync_failed" -eq 1 ] || ! _tunnel_alive "$bg_pid"; }; then
    connect_log 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'
    _action="r"
fi
# then falls into if [ "$_action" = "r" ]; then ... preserve/clear ...
```

Post-q `elif ... _action=r; continue` removed.

---

## 7. PushConf || true

**File:** `scripts/client/git-mode.sh` - `push_server_connect_conf`

### BEFORE

```bash
push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null || true)"
push_ec=$?   # always 0
```

### AFTER ~L134-L140

```bash
# Do not swallow sshx failures with || true - need real exit for RESULT/dedupe gate.
push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null)"
push_ec=$?
result_line="$(printf '%s' "$push_out" | grep PUSH_CONF_RESULT | tail -1 ...)"
if [ "$push_ec" -ne 0 ] || [ -z "$result_line" ]; then
    ... return "${push_ec:-1}"
fi
```

---

## Verification (post-fix)

```bash
laptop-exec rg -p claude-code-server 'timeout 30 sshx' scripts/client/git-mode.sh   # exit 1
laptop-exec rg -p claude-code-server 'seq 1 4' scripts/client/git-mode.sh             # exit 1
laptop-exec rg -p claude-code-server 'seq 1 12|recover-one|action=reseed|banner_miss_tcp_open_budget' scripts/client/git-mode.sh
laptop-exec rg -p claude-code-server 'push_server_connect_conf --clear|if ! tunnel_up|fallthrough_recover' scripts/client/mac/connect.sh
```

Static checks: 12/12 PASS. bash -n OK on both files.
