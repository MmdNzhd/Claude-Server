# STAGE-6e Evidence Pack

## ID
- Stage: 6e (Golden personal-email denylist)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T18:40Z approx
- deploy_ran=no

## VERIFY
- Pre-fix: `cursor-auth-lib.py` / `cursor-auth-export.sh` had no personal-email denylist; any `cachedEmail` could become shared golden.
- Pre-fix: `diagnose-auth.sh` warned "no golden" but did not surface quarantine email/reason.
- No restore of any quarantined-personal golden performed (explicitly avoided).
- still_live=n/a for runtime until next `cursor-auth-export` on server (repo-only; no install).

## RESEARCH
1. https://owasp.org/www-community/attacks/Credential_stuffing — shared/personal email+password reuse risk for shared identities.
2. https://cheatsheetseries.owasp.org/cheatsheets/Credential_Stuffing_Prevention_Cheat_Sheet.html — email-as-username amplifies stuffing; personal domains unsuitable for shared golden.
3. https://cheatsheetseries.owasp.org/cheatsheets/Email_Validation_and_Verification_Cheat_Sheet.html — treat email as weak identifier; avoid logging secrets.

What this changes:
- Default-deny consumer domains (gmail/outlook/yahoo/icloud/proton/…).
- `--allow-personal` escape on export; `ALLOW_PERSONAL_EMAIL` in lib.
- Quarantine reason file (email + reason only, no tokens).
- Diagnose shows email + reason when golden missing after quarantine; Do NOT restore quarantined-personal.

What we will NOT do:
- Deploy / `claude-server install`; restore quarantined personal golden; bump version.

## RED_TEST
```
Pre-patch VERIFY: rg PERSONAL_EMAIL_DOMAIN_DENYLIST → no matches in lib/export/diagnose.
Contract test designed to fail without denylist/hook/--allow-personal/diagnose quarantine lines.
```

## IMPLEMENT
- `scripts/server/cursor-auth-lib.py`: denylist, assert_export_email_allowed, quarantine reason I/O, hook in write_golden_bundle
- `scripts/server/cursor-auth-export.sh`: `--allow-personal` + wire ALLOW_PERSONAL into Python
- `scripts/server/commands/diagnose-auth.sh`: show quarantine email/reason when golden missing
- `scripts/server/tests/test-cursor-auth-personal-denylist.sh`
- drive_by=none; temp helpers removed; quarantined-personal NOT restored

## GREEN_TEST
```
test-cursor-auth-personal-denylist.sh → Passed: 12 Failed: 0
(includes runtime refuse for gmail without flag + --allow-personal escape + work email OK)
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `signature_absent=pending_install` reason=`repo-only; live export/diagnose pick up after future install (not run); quarantine-personal not restored`

## GATE
`STAGE_6e_DONE` 2026-07-22T18:40Z `deploy_ran=no` N+1 unlocked (Stage 10; prune tool before 6d)
