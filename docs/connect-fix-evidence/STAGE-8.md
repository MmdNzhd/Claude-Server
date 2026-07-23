# STAGE-8 Evidence Pack

## ID
- Stage: 8 (`apply_golden_permissions` — dirs 0750 / shared 0640 / exported-at 0644 / sidecars 0600)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T19:55Z approx
- deploy_ran=no

## VERIFY
- Pre-fix: export/refresh used bare `chmod 0700` / `0600` that fought install.sh modes.
- Pre-fix: no shared helper; `write_golden_bundle` modes inconsistent with install.sh.
- Repo-only; do NOT run `claude-server install`.

## RESEARCH
1. https://man7.org/linux/man-pages/man1/chmod.1.html — numeric modes; directory vs file bits.
2. https://hpc.nih.gov/storage/permissions.html — 0750 dirs / 0640 group-readable files.
3. https://www.redhat.com/en/blog/linux-file-permissions-explained — owner/group/other model.

What this changes:
- `apply_golden_permissions()` in `cursor-auth-lib.py` mirrors install.sh (0750/0640/0644/0600).
- Called from `write_golden_bundle`, `cursor-auth-export.sh`, `cursor-auth-refresh.sh`.
- Remove bare GOLDEN_DIR 0700 undos that fight the helper.

What we will NOT do:
- Restore quarantined personal golden; deploy/install.

## RED_TEST
```
Pre-patch: SyntaxError in write_golden_bundle (broken "+ newline" string literals from bad re.sub).
Pre-patch: no apply_golden_permissions; bare 0700 on GOLDEN_DIR in refresh.
```

## IMPLEMENT
- `scripts/server/cursor-auth-lib.py` — helper + call from write_golden_bundle; fixed atomic_write `\n` literals
- `scripts/server/cursor-auth-export.sh` — `mod.apply_golden_permissions()`
- `scripts/server/cursor-auth-refresh.sh` — replace bare 0700 with apply helper
- `scripts/server/tests/test-cursor-auth-golden-perms.sh`
- drive_by=none

## GREEN_TEST
```
test-cursor-auth-golden-perms.sh → All 9 contracts passed.
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `signature_absent=pending_install` reason=`repo cursor-auth-* updated; live /usr/local binaries unchanged until future install (not run)`

## GATE
`STAGE_8_DONE` 2026-07-22T19:55Z `deploy_ran=no` N+1 unlocked (Stage 9)
