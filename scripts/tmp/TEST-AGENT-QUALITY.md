# TEST-AGENT-QUALITY — wave2 Agent Q

**Date:** 2026-07-20  
**Project:** `-p claude-code-server` (laptop-exec only)  
**Tunnel:** UP (`laptop_os=windows`, `active_mount=claude-code-server`)  
**Verdict:** **HARD FAIL** (non-live failures present)

Policy: HARD FAIL counts only non-live failures. LIVE-SKIP called out separately (not counted as hard fail).

---

## Summary table

| # | Gate | Exit | Class | Notes |
|---|------|------|-------|-------|
| 1 | `scripts/client/tests/_scan-unicode.ps1` | **0** | PASS (exit) | Reports smart quotes in comments; does not fail exit |
| 2 | `scripts/client/tests/audit-ps5-deep.ps1` | **1** | **HARD FAIL** | 3× smart-quote asserts |
| 3 | `scripts/client/tests/_parse-check.ps1` (all modified client `.ps1`) | **0** | PASS | All 17 files OK parse |
| 4 | `scripts/client/tests/verify-all.sh` (static only via Git Bash) | **1** | **HARD FAIL** | See LIVE-SKIP + static fails |
| 5 | `scripts/client/tests/test-pipeline-deep.ps1` | **0** | PASS | |
| 6 | `scripts/client/tests/test-pipeline-repro.ps1` | **0** | PASS | |
| 7 | `scripts/client/tests/test-windows-connect.sh` (Git Bash) | **1** | **HARD FAIL** | empty Enter default-project assert |
| 8 | `run-all.ps1` (no-live subset) | **1** | **HARD FAIL** | `connect-pipeline` + `publish` |

**Parser-parse (modified + untracked client `.ps1`):** **0** — all OK (see below).

---

## Gate details

### 1. `_scan-unicode.ps1` — exit 0

Findings (comments / U+201D), exit still 0:

- `connect-ui.ps1` L115
- `git-mode.ps1` L1070, L1093, L1192, L1226
- `editor-launch.ps1` — clean in this scan

### 2. `audit-ps5-deep.ps1` — exit 1 (**HARD FAIL**)

Failed asserts:

- `windows\connect.ps1` no smart quotes
- `connect-ui.ps1` no smart quotes
- `git-mode.ps1` no smart quotes

Parse / en-em dash / `-replace` / Select-String / Set-ConnectTitle checks: PASS.  
Dot-source smoke + `connect.bat` guards: PASS.

### 3. `_parse-check.ps1` / Parser::ParseFile — exit 0

All modified/untracked client `.ps1` from `git status`:

| File | Parse |
|------|-------|
| `scripts/client/connect-diagnostic.ps1` | OK |
| `scripts/client/connect-ui.ps1` | OK |
| `scripts/client/cursor-auth-laptop.ps1` | OK |
| `scripts/client/editor-launch.ps1` | OK |
| `scripts/client/git-mode.ps1` | OK |
| `scripts/client/push-laptop-exec-now.ps1` | OK |
| `scripts/client/tests/test-connect-pipeline.ps1` | OK |
| `scripts/client/tests/test-cursor-auth-merge.ps1` | OK |
| `scripts/client/tests/test-editor-launch-strategies.ps1` | OK |
| `scripts/client/tests/test-git-mode-deep.ps1` | OK |
| `scripts/client/tests/test-publish.ps1` | OK |
| `scripts/client/windows/connect-diagnostic.ps1` | OK |
| `scripts/client/windows/connect-update.ps1` | OK |
| `scripts/client/windows/connect.ps1` | OK |
| `scripts/client/_check-sepidz-auth.ps1` (untracked) | OK |
| `scripts/client/_deploy-sepidz-lex.ps1` (untracked) | OK |
| `scripts/client/_install-bundle-now.ps1` (untracked) | OK |

`PARSE_FAIL_COUNT=0`

### 4. `verify-all.sh` — static via Git Bash — exit 1 (**HARD FAIL**)

`verify-all.sh` loops all `scripts/client/tests/test-*.sh`. Live suite skipped.

| Script | Result |
|--------|--------|
| `test-client-auto-update.sh` | **FAIL** — `grep: -P supports only unibyte and UTF-8 locales` (exit 2) |
| `test-cursor-auth-merge.sh` | **FAIL** — `merge_cursor_auth_into_local_db failed` |
| `test-mac-laptop-ssh-live.sh` | **LIVE-SKIP** |
| `test-mac-laptop-ssh.sh` | OK |
| `test-project-rpath.sh` | OK |
| `test-server-tunnel-check.sh` | OK |
| `test-windows-connect.sh` | **FAIL** — see gate 7 |

Publish-sync block in `verify-all.sh` (Desktop `claude-code-client-20260704`) not re-run separately; static `test-*.sh` failures already fail the gate.

### 5–6. Pipeline tests — exit 0

Both `test-pipeline-deep.ps1` and `test-pipeline-repro.ps1` passed.

### 7. `test-windows-connect.sh` — exit 1 (**HARD FAIL**)

```
FAIL: empty Enter must not select default project
```

Assert (line 27): expects `if (-not $c) { continue }` in `windows/connect.ps1`.

Runner: Git Bash `C:\Program Files\Git\bin\bash.exe` from repo root (LF copy same path depth so `$0`-based `ROOT` resolves).

### 8. `run-all.ps1` — read + no-live run — exit 1 (**HARD FAIL**)

#### What `run-all.ps1` does

Orchestrates local PowerShell regression suites under `scripts/client/tests/`. It does **not** open an SSH session to production Smart/Sepidz for connect. Suites are file/AST/static (plus optional local WMI).

Included suites:

- pipeline-deep, pipeline-repro, connect-ui, select-project, connect-pipeline
- laptop-ssh-ready (local helpers; not prod SSH)
- git-mode-deep, editor-launch, editor-launch-strategies
- connect-diagnostic, parse-connect-perf, verify-perf-gates
- **launch-perf-live** ← live WMI / Cursor-on-folder timing
- cursor-auth-merge, publish
- then `audit-local-connect.ps1` (informational; non-SAFE Desktop copies expected)

#### LIVE-SKIP for this wave

| Item | Why skipped |
|------|-------------|
| `test-launch-perf-live.ps1` | Live WMI timing when Cursor already on known remote folder; optional; can exit 0 on SKIP |
| `test-mac-laptop-ssh-live.sh` (via verify-all) | Live reverse-SSH / tunnel self-heal against alias |

**Not skipped as “prod SSH”:** remaining `run-all.ps1` suites — they are local script audits. Desktop publish folder checks in `test-publish.ps1` inspect already-built ZIPs on the laptop Desktop (not a live SSH connect to prod).

#### No-live `run-all` results

| Suite | Exit / note |
|-------|-------------|
| pipeline-deep | PASS |
| pipeline-repro | PASS |
| connect-ui | PASS |
| select-project | PASS |
| connect-pipeline | **FAIL** (exit 1) — smart/curly quotes in `windows\connect.ps1` |
| laptop-ssh-ready | PASS |
| git-mode-deep | PASS |
| editor-launch | PASS |
| editor-launch-strategies | PASS |
| connect-diagnostic | PASS |
| parse-connect-perf | PASS |
| verify-perf-gates | PASS |
| launch-perf-live | **LIVE-SKIP** |
| cursor-auth-merge | PASS |
| publish | **FAIL** (exit 1) — 14 asserts (stale Desktop publish trees / file-count / sepidz alias / binary identical / etc.) |
| audit-local-connect | Informational; many [BROKEN] old Desktop copies (not counted as suite fail in runner) |

Aggregate no-live: **2 suite(s) failed** → exit **1**.

---

## Cross-cutting root themes (non-live)

1. **Smart / curly quotes (U+201C/U+201D)** in production PS1 comments/strings → fails `audit-ps5-deep`, `test-connect-pipeline`, and is reported by `_scan-unicode` (exit 0).
2. **`windows/connect.ps1` missing** `if (-not $c) { continue }` for empty Enter on project select → `test-windows-connect.sh`.
3. **Bash static suite issues on Windows Git Bash:** `test-client-auto-update.sh` (`grep -P` locale); `test-cursor-auth-merge.sh` merge helper failure.
4. **Stale Desktop publish packages** vs current repo expectations → `test-publish.ps1` (14 fails). Treat as quality gate fail for published artifacts on this laptop, not necessarily as source-tree logic alone.

---

## LIVE-SKIP register (not HARD FAIL)

| ID | Location | Reason |
|----|----------|--------|
| LIVE-SKIP-1 | `run-all.ps1` → `test-launch-perf-live.ps1` | Live Cursor/WMI launch timing |
| LIVE-SKIP-2 | `verify-all.sh` → `test-mac-laptop-ssh-live.sh` | Live Mac reverse-SSH / tunnel |

---

## Overall

**HARD FAIL.** Non-live exits non-zero: gates **2, 4, 7, 8** (and `connect-pipeline` / `publish` within 8). Gates **1 (exit), 3, 5, 6** and Parser-parse of modified client PS1: **PASS**.
