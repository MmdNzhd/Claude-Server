# Agent-path diag logs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use parallel-phased-execution. Steps use checkbox (`- [x]`) syntax.

**Goal:** Sparse diagnostic logs so Connect green + agent dead (missing TUNNEL_PORT) and SSH slowness are visible without flooding the day log.

**Architecture:** Observe-only. Fail-open. Dual-UI `session_port != conf_port` is OK when `conf_port` listens.

## File map

| File | Responsibility |
|------|----------------|
| `scripts/client/connect-ui.ps1` | AGENT_PATH 60s probe + SCORECARD `port=` |
| `scripts/client/windows/connect.ps1` | SSH ms ring + SSH_ROLLUP |
| `scripts/client/git-mode.ps1` / `.sh` | WARN on ABORT_EMPTY / port_empty_recovered / port_mismatch_keep |
| `scripts/server/laptop-exec.sh` | TUNNEL_PORT_MISSING stderr+audit |
| `scripts/client/connect-ui.sh` + `mac/connect.sh` | Mac parity |
| `scripts/client/tests/test-agent-path-diag-logs.ps1` | Contract tests |

## Wave table

### Step 1 — Implement (parallel, write-disjoint)

| Worker | Owns |
|--------|------|
| W1 | connect-ui.ps1 |
| W2 | windows/connect.ps1 |
| W3 | git-mode.ps1 + git-mode.sh |
| W4 | laptop-exec.sh |
| W5 | connect-ui.sh + mac/connect.sh |

### Step 2 — Tests + ship (after Step 1 gate)

| Worker | Owns |
|--------|------|
| W6 | test-agent-path-diag-logs.ps1 + run focused tests |
| W7 | publish -SmartOnly + deploy laptop-exec |

## Contracts

- AGENT_PATH: ≤1/60s; probe timeout 3s; WARN only conf_missing|conf_empty|conf_port_closed|probe_fail
- SSH_ROLLUP: ≤1/60s OR after ≥30 samples once 60s elapsed; fields count/min/p50/p90/max/over_2s/over_5s
- SCORECARD keeps existing keys; append `port=`
- No secrets; no tunnel/mount/editor behavior change

## Risks

- Extra SSH every 60s → keep cmd tiny, timeout 3s, fail-open
- Dual-UI false WARN → do not treat port mismatch alone as bad

