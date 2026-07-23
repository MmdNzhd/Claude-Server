# STAGE-6c Evidence Pack

## ID
- Stage: 6c (Defender/SmartScreen false positive docs)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T18:05Z approx
- deploy_ran=no

## VERIFY
- Pre-fix: `docs/client-connect.md` already said folder primary, but lacked SmartScreen/Defender FP guidance (MOTW Unblock, scoped exclusion, Authenticode, WDSI).
- Pre-fix: `publish/README.txt` still preferred EXE-only Option A ("single file — preferred for users").
- Pre-fix: `publish/build-windows-exe.ps1` header told publishers to give EXE only (not the windows\ folder).
- No script ever disabled Defender (confirmed); docs also never advised it after this stage.
- still_live=n/a (docs-only; no runtime signature).

## RESEARCH
1. https://support.microsoft.com/en-gb/topic/information-about-the-attachment-manager-in-microsoft-windows-c48a4dcd-8de5-2af5-ee9b-cd795ae42738 — Attachment Manager / MOTW; Unblock via file Properties.
2. https://www.microsoft.com/en-us/wdsi/filesubmission — Microsoft Security Intelligence false-positive / incorrect detection submission portal.
3. https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/microsoft-defender-smartscreen-overview — SmartScreen app reputation for unsigned / low-reputation downloads.

What this changes:
- Docs: folder/ZIP primary; unsigned IExpress FP; Allow/Unblock MOTW; exclusion only Desktop\Claude-Connect; Authenticode OV+timestamp future path; WDSI link; never disable Defender.
- README Option A = folder/ZIP primary; Option B = optional EXE fallback + SMARTSCREEN section.
- build-windows-exe.ps1 header points at docs (optional).

What we will NOT do:
- Publish EXE; deploy; disable Defender; Authenticode signing in this stage.

## RED_TEST
```
test-smartscreen-docs-contract.ps1 → Passed: 6 Failed: 10
(pre-patch; README preferred EXE; no SmartScreen/Defender FP/MOTW/WDSI/exclusion docs)
```

## IMPLEMENT
- `docs/client-connect.md`: expanded Windows Smart package layout + SmartScreen/Defender FP subsection
- `publish/README.txt`: folder/ZIP primary; EXE optional; SMARTSCREEN / DEFENDER FALSE POSITIVES section
- `publish/build-windows-exe.ps1`: header comments → folder primary + FP pointer
- `scripts/client/tests/test-smartscreen-docs-contract.ps1` + register in `run-all.ps1`
- drive_by=none (temp `_stage6c-patch.ps1` / `_fix-6c-test.ps1` removed)

## GREEN_TEST
```
test-smartscreen-docs-contract.ps1 → Passed: 20 Failed: 0
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `signature_absent=n/a` reason=`docs-only stage; live user guidance verified by contract test; no client runtime change`

## GATE
`STAGE_6c_DONE` 2026-07-22T18:05Z `deploy_ran=no` N+1 unlocked (Stage 6f; exec order 6c then 6f then 6e then 10 then 6d then 7-11)
