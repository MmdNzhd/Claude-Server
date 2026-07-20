# HARD-GAP: PowerShell Pre-Definition Top-Level Call Audit

**Date:** 2026-07-20  
**Project:** `claude-code-server`  
**Scope:** `scripts/client/**/*.ps1` (60 files)  
**Bug class:** Top-level / immediate script-body call to a function defined later in the same file (same class as historical `Ensure-ConnectRunId` in `connect-update.ps1`).

## Method

1. **Primary scan:** PowerShell AST analyzer (`scripts/tmp/ps1_predef_analyzer.ps1`) using `[System.Management.Automation.Language.Parser]::ParseFile`.
2. **Rules:**
   - Collect `FunctionDefinitionAst` nodes → first definition line per function name.
   - Collect top-level executable statements (exclude `function`, `trap`, `using`, `class` blocks).
   - Flag when a `CommandAst` invokes a function name defined **later** in the same file.
   - Ignore calls inside `trap` bodies (deferred until error; guarded patterns like `Get-Command` are not flagged).
   - Ignore calls inside function bodies (only invoked when those functions run).
3. **Secondary scan:** Python line-based analyzer (server-side, files fetched via `laptop-exec read`) — same result.
4. **Priority files manually reviewed:** `windows/connect-update.ps1`, `connect-ui.ps1`, `windows/connect.ps1`, `git-mode.ps1`, `editor-launch.ps1`, `cursor-auth-laptop.ps1`.

## FAIL — Top-level call before definition

| File | Function | Def line | Call line |
|------|----------|----------|-----------|
| *(none)* | | | |

**FAIL count:** 0

## PASS summary

| Metric | Value |
|--------|-------|
| Files scanned | 60 |
| PASS | 60 |
| FAIL | 0 |

### Priority files (explicit PASS)

| File | Status |
|------|--------|
| `scripts/client/windows/connect-update.ps1` | PASS — `Ensure-ConnectRunId` defined line 16, first top-level call line 31 |
| `scripts/client/connect-ui.ps1` | PASS — library-only; no top-level calls after param block |
| `scripts/client/windows/connect.ps1` | PASS — dot-sources siblings before calling their functions |
| `scripts/client/git-mode.ps1` | PASS |
| `scripts/client/editor-launch.ps1` | PASS |
| `scripts/client/cursor-auth-laptop.ps1` | PASS |

### All PASS files

- `scripts/client/_check-sepidz-auth.ps1`
- `scripts/client/_deploy-sepidz-lex.ps1`
- `scripts/client/_install-bundle-now.ps1`
- `scripts/client/connect-diagnostic.ps1`
- `scripts/client/connect-ui.ps1`
- `scripts/client/cursor-auth-laptop.ps1`
- `scripts/client/deploy-server-mount-fix.ps1`
- `scripts/client/editor-launch.ps1`
- `scripts/client/git-mode.ps1`
- `scripts/client/push-laptop-exec-now.ps1`
- `scripts/client/sync-desktop.ps1`
- `scripts/client/tests/*.ps1` (44 test/diag scripts)
- `scripts/client/users/designer/connect.ps1`
- `scripts/client/verify-push.ps1`
- `scripts/client/windows/connect-design.ps1`
- `scripts/client/windows/connect-diagnostic.ps1`
- `scripts/client/windows/connect-update.ps1`
- `scripts/client/windows/connect.ps1`

## Overall result

# **PASS**

No PowerShell client scripts in scope contain an unguarded top-level call to a same-file function that is defined later. The historical `Ensure-ConnectRunId` ordering bug in `connect-update.ps1` is **not present** in the current tree (function now precedes its first top-level invocation).

## Analyzer artifacts

- `scripts/tmp/ps1_predef_analyzer.ps1` — AST scanner (deployed on laptop for reproducibility)
- Server-side helper: `/tmp/analyze_ps1_predef.py` (Python + `laptop-exec read`, confirmatory)
