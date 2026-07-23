# STAGE-7 Evidence Pack

## ID
- Stage: 7 (laptop-exec timeout -k 5; RUN default 120; CMD_END on 124)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T19:40Z approx
- deploy_ran=no

## VERIFY
- Pre-fix: `timeout --foreground` without `-k 5` (kill-after grace).
- Pre-fix: `LAPTOP_EXEC_RUN_TIMEOUT:-600` (usage said run 600s).
- Pre-fix: exit 124 logged CMD_TIMEOUT in `_laptop_ssh` but no dedicated `CMD_END … meaning=timeout` branch in `main`.
- Repo-only; do NOT run `claude-server install`.

## RESEARCH
1. https://man7.org/linux/man-pages/man1/timeout.1.html — `-k` kill signal after grace if command ignores first signal.
2. https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html — `--foreground` for interactive/SSH child trees.
3. https://man.openbsd.org/ssh.1 — ControlMaster mux; hung remote cmds pin channels without wall-clock timeout.

What this changes:
- `timeout -k 5 --foreground`
- RUN default 120s; usage text updated
- Explicit CMD_END exit=124 meaning=timeout

What we will NOT do:
- `claude-server install` / deploy live binary.

## RED_TEST
```
Pre-patch: no `timeout -k 5`; RUN default 600; no meaning=timeout CMD_END.
```

## IMPLEMENT
- `scripts/server/laptop-exec.sh` (repo only)
- `scripts/server/tests/test-laptop-exec-timeout-audit.sh`
- drive_by=none

## GREEN_TEST
```
test-laptop-exec-timeout-audit.sh → Passed: 7 Failed: 0
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `signature_absent=pending_install` reason=`repo laptop-exec.sh updated; live /usr/local/bin/laptop-exec unchanged until future install (not run)`

## GATE
`STAGE_7_DONE` 2026-07-22T19:40Z `deploy_ran=no` N+1 unlocked (Stage 8)
