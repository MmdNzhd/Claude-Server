# FIX-CREDS-CURLY-DONE

Date: 2026-07-20  
Project: `claude-code-server` (laptop-exec `-p claude-code-server`)  
Deploy: **NOT run** (per request)

## A) Credentials

### Changes
- `publish/Get-DeployCredentials.ps1`
  - No hardcoded password defaults (`sepidz@Admin` or similar).
  - Missing `publish/sepidz-deploy.local.ps1` / `publish/smart-deploy.local.ps1` → **throw** with clear copy-from-example message.
  - Empty password in local file → throw.
  - Only sources: env (`SEPIDZ_SUDO_PASSWORD` / `SMART_SUDO_PASSWORD`) or gitignored local files.
- `publish/deploy-client-bundles.ps1`
  - Still calls `Get-SepidzSudoPassword` / `Get-SmartSudoPassword` only (no inline password fallback).
  - Comment cleaned of em-dash.
- Examples only (placeholders, not secrets):
  - `publish/sepidz-deploy.local.ps1.example` → `YOUR_SEPIDZ_SUDO_PASSWORD`
  - `publish/smart-deploy.local.ps1.example` → `YOUR_SMART_SUDO_PASSWORD`
- `.gitignore` now includes:
  - `*-deploy.local.ps1`
  - `publish/*-deploy.local.ps1`

### Verify
- Scripted scan of publish credential scripts: **no** `sepidz@Admin`, **no** real `$SepidzSudoPassword = '...'` / `$SmartSudoPassword = '...'` assignments outside examples.

## B) Curly quotes / Unicode dashes

### Root cause
UTF-8 em-dashes (`U+2014`, bytes `E2 80 94`) in comments were decoded by default Windows `Get-Content` as including `U+201D` (curly quote), so `test-connect-pipeline.ps1` assert failed even when UTF-8-aware scans looked “almost clean”.

### Fixed (replaced `U+201C/D/8/9` and `U+2013/14` with ASCII; stripped BOM where present)
Notable files among others under `scripts/client` + `publish`:
- `scripts/client/windows/connect.ps1`
- `scripts/client/connect-ui.ps1` / `connect-ui.sh`
- `scripts/client/git-mode.ps1` / `git-mode.sh`
- `scripts/client/editor-launch.ps1` / `editor-launch.sh`
- `scripts/client/windows/connect-update.ps1`
- `scripts/client/mac/connect.sh` / `connect-update.sh`
- `publish/deploy-client-bundles.ps1`
- `.gitignore` (comment dash)

Post-fix scan of `scripts/client` + `publish` `*.ps1|*.bat|*.sh` (excluding `*.local.ps1`): **STILL_BAD_COUNT=0**.

### Exact assert
From `test-connect-pipeline.ps1`:
```powershell
Assert ($src -notmatch '[\u201C\u201D\u2018\u2019]') "$rel has no smart/curly quotes (PS 5.1 break)"
```
Result: **PASS**

## Pipeline

Command:
```powershell
powershell -NoProfile -File scripts/client/tests/test-connect-pipeline.ps1
```

**Exit code: 0** (All tests passed.)

## Not done
- No `claude-server` / client bundle deploy.
- No commit (not requested).
