# Task 5+ — Remaining cold-start cuts (Admit still FAIL at 15024 ms)

## Evidence (session `35176202e721`, v20260726.01)

| Span | ms | Notes |
|------|-----|-------|
| click → menu | 15024 | FAIL vs ≤5000 |
| BOOTSTRAP 10:13:49.038 → UPDATE up_to_date 10:13:53.278 | ~4240 | bootstrap SSH + **heal PS (~2.4s)** + update SSH |
| UPDATE → session start 10:13:56.415 | ~3137 | connect-boot cold start |
| Server setup | 4378 | includes ~2s Ensure#1 / Get-NetFirewallRule |
| Loading projects | 674 | OK |

Contracts already PASS: `drift_gate=script_only_ok`, no pre-menu tunnel/sidecar.

## Goal
Cut enough critical-path work that a fresh live run can hit **≤5000 ms** click→`project_menu_shown` (or get as close as possible with evidence).

## Required changes (priority order)

### A) Skip Quiet update when bootstrap already proved version match
- `connect-bootstrap.ps1`: when it logs `BOOTSTRAP_PULL: skip canon already current` (or equivalent), set for parent handoff:
  - Prefer writing a small temp handoff file (bat can read) OR exit code convention — **child env does not reach bat**.
  - Practical approach: write `%TEMP%\claude-connect-preflight.ok` (or reuse existing temp pattern) with lines like `REMOTE_VER=...` / `SKIP_UPDATE=1` when versions match and no pull needed.
- `connect.bat` or `connect-preflight.ps1`: after bootstrap success, if handoff says skip update → **do not spawn** `connect-update.ps1`.
- Still run update when bootstrap pulled/forced or versions differ or heal redirected.

### B) Skip heal on healthy current deploy
- When bootstrap reports already current AND local deploy looks complete (connect.ps1 + connect-boot + cursor-proxy-sidecar + version match), **skip heal spawn** in preflight.
- Keep heal on: bootstrap force/pull, missing files, OUTDATED paths, heal exit-2 redirects.
- Bat already sets SKIP_HEAL after full preflight success — this skips the **preflight** heal itself (~2.4s).

### C) Firewall probe cost on Ensure#1 (~2s)
- In `Test-LaptopSshReady` / Ensure path: if OpenSSH sshd is Running AND a short-TTL cache file says firewall OK (e.g. `%TEMP%\claude-connect-fw-ok.txt` age < 24h or session+disk), skip `Get-NetFirewallRule`.
- Invalidate cache when Ensure fails or AdminFix runs.
- Must not skip when sshd is stopped.

### D) Tests (TDD)
- New or extended tests for:
  - preflight skips update when bootstrap handoff SKIP_UPDATE=1
  - preflight skips heal when bootstrap already-current + healthy files
  - firewall cache skip path (unit/source contract OK if live CIM hard)
- Re-run: `test-connect-preflight-skip-heal.ps1`, new tests, `test-connect-pipeline.ps1`

### E) Redeploy + live re-Admit
- Bump version to **`20260726.02`** (all version sites)
- `publish.ps1 -SmartOnly -SkipVersionBump`
- Live measure again; write numbers to report
- DO NOT commit

## Owns (write-set)
- `scripts/client/windows/connect-bootstrap.ps1`
- `scripts/client/windows/connect-preflight.ps1`
- `scripts/client/windows/connect.bat` (handoff read if needed)
- `scripts/client/windows/connect.ps1` (firewall cache only)
- version sites + tests + report

## Anti-patterns
- Do not remove Server setup hard Ensure when sshd down
- Do not skip update forever without a version check somewhere in the cold path (bootstrap check counts)
- Do not re-enable pre-menu tunnel

## Report
`D:\Smart\Claude-Code-Server\.superpowers\sdd\briefs\task-5-plus-report.md`
ADMIT PASS/FAIL with ms.
