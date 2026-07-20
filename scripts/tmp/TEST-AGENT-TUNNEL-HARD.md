# TEST-AGENT-TUNNEL-HARD — Wave2 Agent N

**Verdict: HARD FAIL**

Date: 2026-07-20  
Project: `-p claude-code-server`  
Scope: tunnel softfail / banner_miss / Ensure-SessionTunnel / wait_for_tunnel / recover_mounts / EditorSeenOpen

## Artifacts

| Artifact | Path | Result |
|---|---|---|
| Git-mode deep | `scripts/tmp/TEST-GITMODE2-OUT.txt` | PASS (all deep git-mode tests passed, EXIT=0) |
| Contract script | `scripts/tmp/test-tunnel-contracts.ps1` | EXIT=1 |
| This report | `scripts/tmp/TEST-AGENT-TUNNEL-HARD.md` | HARD FAIL |

## Contract results (Select-String static)

| # | Assertion | Result |
|---|---|---|
| 1a | Win SoftFailCount `-lt 6` threshold present | PASS |
| 1b | Win SoftFailCount `-ge 6` → `TUNNEL_DROP` or `return $false` on **no_proc_tcp_open** path | **FAIL** |
| 1c | Mac SoftFail budget → `TUNNEL_DROP` (`no_ssh_proc_tcp_open_budget`) | PASS |
| 2a | Win+Mac `banner_miss_tcp_open` present | PASS |
| 2b | Win+Mac banner_miss budgets toward DROP (`banner_miss_tcp_open_budget` + count soft_fail) | PASS |
| 3 | Ensure-SessionTunnel / ensure_session_tunnel does **not** return success solely on banner_miss | PASS (both `action=reseed`, fall through) |
| 4 | Mac `wait_for_tunnel_up` uses `seq 1 12` | PASS |
| 5 | Mac `recover_mounts_if_needed`: single remote `sshx`; no nested sshx | PASS |
| 6 | Win `EditorSeenOpen` cleared when editor not open (`EDITOR_SEEN_CLEAR` session_poll) | PASS |

**Contracts: 12 passed, 1 failed → exit 1**

## HARD FAIL detail

### Win `no_proc_tcp_open` SoftFail budget does not DROP

In `scripts/client/git-mode.ps1` (`Sync-SessionTunnelProcess`):

- SoftFail increments and logs `reason=no_proc_tcp_open`.
- If `TunnelSoftFailCount -lt 6` → `return $true` (soft continue) — OK.
- When count reaches **6**, there is **no** `TUNNEL_DROP` and **no** `return $false` in that block.
- Control falls through to later branches (`bg_alive` / `Test-TunnelUp`), which can keep the session soft-alive forever on TCP-open-without-proc.

Mac counterpart correctly emits `TUNNEL_DROP` / `reason=no_ssh_proc_tcp_open_budget` after soft-fail budget exhaustion.

**Required fix:** After SoftFailCount budget exhaustion on the Win `no_proc_tcp_open` path, emit `TUNNEL_DROP` and `return $false` (mirror Mac / Win `banner_miss_tcp_open_budget`).

## What already passes (regression-relevant)

- Banner miss increments SoftFail and DROPs at 6 (`banner_miss_tcp_open_budget`) on Win+Mac.
- Ensure* no longer treats `banner_miss_tcp_open` as session success; reseeds.
- Mac tunnel wait uses 12 attempts; recover is one remote command (no `sshx`-inside-`sshx`).
- Win clears `EditorSeenOpen` when the editor window is closed (session poll / open / recovery / finally).

## Commands used

```text
laptop-exec run -p claude-code-server -- powershell -File scripts/tmp/run-gitmode2.ps1
laptop-exec run -p claude-code-server -- powershell -File scripts/tmp/run-contracts.ps1
```

## Final status

**HARD FAIL** — Win SoftFailCount ≥ 6 on `no_proc_tcp_open` still soft-continues only.
