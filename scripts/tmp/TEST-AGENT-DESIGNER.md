# TEST-AGENT-DESIGNER — HARD wave2 Agent K

**Project:** `claude-code-server` (laptop-exec only, no deploy)  
**Date:** 2026-07-20  
**Verdict: HARD FAIL**

---

## Scope files

| Path | Role |
|------|------|
| `scripts/client/users/designer/connect.ps1` | Designer connect (Windows) |
| `scripts/client/windows/connect-design.ps1` | Claude Design / noVNC fork |
| `scripts/client/connect-ui.ps1` | Shared UI + single-instance mutex (main connect) |
| `scripts/client/tests/test-connect-ui.ps1` | Unit test |
| `scripts/client/windows/connect.ps1` | Main connect (baseline for mutex / useVk / ClearActiveMount) |
| `scripts/client/git-mode.ps1` | `Push-ServerConnectConf`, `Read-RetryQuitKey` |

`laptop-exec rg -l "designer|connect-design" scripts/client` also hit README + `.sh` (out of PS parse scope).

---

## 1. Parser::ParseFile

| File | Result |
|------|--------|
| `scripts/client/users/designer/connect.ps1` | PARSE_OK |
| `scripts/client/connect-ui.ps1` | PARSE_OK |
| `scripts/client/windows/connect-design.ps1` | PARSE_OK |
| `scripts/client/tests/test-connect-ui.ps1` | PARSE_OK |
| `scripts/client/tests/test-select-project.ps1` | PARSE_OK |

Parse errors: **0** (not a fail axis).

---

## 2. Static HARD asserts (HIT = FAIL)

### HIT A — KeyChar / physical Key for Q/quit **without** `useVk` gating

**Baseline (main `connect.ps1`):** quit uses ASCII KeyChar letter **or** `useVk`-gated `ConsoleKey::Q` (VK only when KeyChar is null/control — never Persian printable).

| File | Evidence | HIT |
|------|----------|-----|
| `connect-design.ps1` L287–289 | `$kc2 -eq 'q' -or $ki2.Key -eq [ConsoleKey]::Q` — no `useVk` | **HIT** |
| `connect-design.ps1` L328–332 | `$kc -eq 'q' -or $ki.Key -eq [ConsoleKey]::Q -or Enter` — no `useVk` | **HIT** |
| `connect-design.ps1` L352–354 | same ungated Q pattern on kick menu | **HIT** |
| `designer/connect.ps1` session loop L543–546 | no Q letter/`useVk`; **any** non-R/G key leaves default quit (see HIT B). R/G also use ungated `$ki.Key -eq ConsoleKey::R/G` (Persian VK false-positive risk; not the Q assert but related drift from main) | partial / related |
| `designer/connect.ps1` post-menu L611–617 | C/X use KeyChar **or** ungated `ConsoleKey` (no `useVk`) | related |

### HIT B — default `$action = 'q'` on key read

| File | Evidence | HIT |
|------|----------|-----|
| `designer/connect.ps1` L538 | `$action = 'q'` before wait; any non-R/G key → disconnect | **HIT** |
| `connect-design.ps1` L323 | `$action = 'q'` before wait | **HIT** |

Main connect resolves keys with explicit ignore of non-command keys; does not pre-seed quit.

### HIT C — `ActiveMount ''` without `ClearActiveMount` / `--clear`

`Push-ServerConnectConf` (`git-mode.ps1` L999–1014): empty `-ActiveMount` does **not** clear. Clear only when `-ClearActiveMount`. Empty prefer falls through to `$script:ActiveProjectId` or existing conf `ACTIVE_MOUNT`.

| File | Evidence | HIT |
|------|----------|-----|
| `designer/connect.ps1` L438, L502, L570, L591 | `Push-ServerConnectConf -ActiveMount ''` (4×) | **HIT** |
| Main `connect.ps1` | uses `Push-ServerConnectConf -ClearActiveMount` | OK (baseline) |
| `connect-design.ps1` | no ActiveMount push (N/A for this assert) | — |

**Effect:** designer “disconnect clear” may **fail to clear** server `ACTIVE_MOUNT` while `$script:ActiveProjectId` is still set (L507 sets it after mount).

### HIT D — missing mutex / single-instance vs main connect

| File | Evidence | HIT |
|------|----------|-----|
| `connect-ui.ps1` L70–101 | `Enter-ConnectSingleInstance` / `Exit-ConnectSingleInstance` (named `Mutex`) | present in shared UI |
| Main `connect.ps1` L178–179 | calls `Enter-ConnectSingleInstance` | OK |
| `designer/connect.ps1` | dotsources `git-mode.ps1` only — **no** `connect-ui.ps1`, **no** mutex | **HIT** |
| `connect-design.ps1` | standalone; **no** mutex / single-instance | **HIT** |

---

## 3. Tests (exit codes)

| Test | Exit | Result |
|------|------|--------|
| `scripts/client/tests/test-connect-ui.ps1` | **0** | OK (prints `OK test-connect-ui.ps1`) |
| `scripts/client/tests/test-select-project.ps1` | **0** | All select-project tests passed |

Tests cover **main** connect-ui / Choose-Project patterns — they do **not** exercise designer or connect-design forks. Passing tests **do not** clear static HITs.

---

## 4. Ruthless summary

| Axis | Status |
|------|--------|
| Parse | PASS |
| HIT A KeyChar/Key Q without useVk | **FAIL** (`connect-design.ps1`) |
| HIT B default action `'q'` | **FAIL** (designer + connect-design) |
| HIT C ActiveMount `''` without clear | **FAIL** (designer ×4) |
| HIT D missing mutex vs main | **FAIL** (designer + connect-design) |
| test-connect-ui / test-select-project | PASS (exit 0) |

### OVERALL: **HARD FAIL**

Designer and connect-design forks diverged from main connect’s Persian-safe key gating, ActiveMount clear switch, and single-instance mutex. Automated UI tests green ≠ fork parity.

