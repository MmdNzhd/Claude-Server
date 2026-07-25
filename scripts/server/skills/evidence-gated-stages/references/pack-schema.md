# Evidence Pack Schema

Path: `docs/<feature>-evidence/STAGE-<id>.md`  
Empty required section ⇒ **INVALID** ⇒ stage **FAILED**.

## Required H2 sections

| Section | Aliases accepted by validator |
|---------|-------------------------------|
| ID | — |
| VERIFY | — |
| RESEARCH | — |
| RED_TEST | RED |
| IMPLEMENT | — |
| GREEN_TEST | GREEN |
| RUNTIME_GATE | LIVE_GATE |
| ARTIFACT_SYNC | — |
| GATE | — |

## Field checklist per section

### ID
- Stage id (`0`, `1`, `1b`, `6d`, `D`, …)
- Baseline/version at start
- Timestamp `YYYY-MM-DDTHH:MMZ`
- `deploy_ran=yes|no`

### VERIFY
- Live fingerprint: `session=` / time / exact substring
- Code anchor: `path:symbol` or lines
- `still_live=yes|no` + proof
- Identity: `repo=… artifact=… live=…`

### RESEARCH
- ≥2 citations: `https://…` **or** in-repo paths (`docs/…`, `*.md`)
- Changes bullets
- Will-NOT-do bullet

### RED_TEST
- Command(s)
- Failing excerpt (assertion name + message)
- Baseline stage may set `N/A reason=…`

### IMPLEMENT
- File list
- One-sentence intent
- `drive_by=none` (or explicit list — prefer none)
- Optional `sync_set:` roots/files for ARTIFACT_SYNC

### GREEN_TEST
- Same command(s) as RED
- Pass summary line counts

### RUNTIME_GATE
- `signature_absent=yes` **or** `pending_reconnect` **or** `N/A`
- reason required unless `yes` with proof substring

### ARTIFACT_SYNC
- Sync set listed (files/roots)
- SHA12 or version-file proof for each root, **or** `n/a reason=…`
- Partial sync ⇒ invalid

### GATE
```
STAGE_<id>_DONE YYYY-MM-DDTHH:MMZ deploy_ran=no N+1 unlocked
```
Pack GATE keeps `STAGE_<id>_DONE` for the validator. Chat progress should say
`CANDIDATE_COMPLETE` — pack DONE ≠ Product DONE ([propose-admit](propose-admit.md)).
Release packs: `deploy_ran=yes` + command list in IMPLEMENT/VERIFY.

## Special packs

| Type | Relaxations |
|------|-------------|
| Baseline (0) | RESEARCH/RED/GREEN may be N/A with reason; must have gun list in VERIFY |
| Investigate-only | IMPLEMENT = notes only / no production files; still need RED contract if claiming a mechanism |
| Release (D) | VERIFY quotes user unlock; RUNTIME_GATE post-release |

## Progress line

```text
STAGE_<id>_DONE pack=<path> deploy_ran=no repo_green=yes|no runtime_green=yes|pending|n/a artifact_sync=yes|n/a
```

## Directory layout

```text
docs/<feature>-evidence/
  STAGE-0.md
  STAGE-1.md
  HYPOTHESES.md
  CLOSEOUT.md
```

## Validator scope

`scripts/validate-pack.py` checks **structure** (required H2s, `deploy_ran` in ID, RESEARCH citations ≥2, GATE line, RUNTIME_GATE not template-empty, release-cmd contradiction).

Default checks now include basic GREEN-without-RED and ARTIFACT_SYNC shape; `--strict` requires `drive_by=`.
Still **not** fully enforced: P0 waiver registry, honest SHA values, or that a live gun scan actually ran. Those remain execute/closeout MUST rules + [propose-admit](propose-admit.md).
