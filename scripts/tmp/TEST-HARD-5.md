# TEST-HARD-5 — Mount Safety Hard Verification

**Agent:** T5 (subagent)  
**Project:** `claude-code-server` (`-p claude-code-server`)  
**Date:** 2026-07-20  
**Deploy:** none  

## OVERALL: **PASS**

---

## 1. Contract scripts (`*mount*contract*`)

| Script | Result |
|--------|--------|
| `scripts/tmp/test-mount-contracts.ps1` | **PASS** (exit 0) |

No other `*mount*contract*` executables found (only prior `.out`/`.err` artifacts).

### Contract run output

```
PASS: no Remove-Item -Recurse on .git
PASS: _restore_git_body has no Remove-Item (rename-only)
PASS: watchdog DOWN restores git with/before umount
PASS: empty ACTIVE_MOUNT does not alphabetical-fallback
PASS: mount _load_global strips CR (tr -d present)
PASS: hide_try skips worktree .git file (PathType check)

HARD PASS: all mount contracts
```

---

## 2. Static mount-safety checks

### 2.1 No alphabetical ACTIVE_MOUNT fallback — **PASS**

| File | Evidence |
|------|----------|
| `scripts/server/claude-automount.sh` | Comment + logic: infer from `LAST_ACTIVE` only; explicit “Do NOT write first alphabetical conf as ACTIVE_MOUNT when empty”. |
| `scripts/server/claude-watchdog.sh` | `_infer_active()` order: existing ACTIVE_MOUNT → LAST_ACTIVE → mounted lpath scan; ends with `return 1` and comment “Do NOT pick first alphabetical conf”. |
| Grep | No `ACTIVE_MOUNT="$_id"; break` or `[ -n "$name" ] && { printf` alphabetical picker in live code. |

### 2.2 Watchdog uses `claude-mount down` — **PASS**

`scripts/server/claude-watchdog.sh` tunnel-DOWN branch:

```bash
if [ -x "$MOUNT_BIN" ]; then
    "$MOUNT_BIN" down 2>/dev/null || true
fi
```

Comment documents that `claude-mount down` restores `.git` from `.git.server-session` when TCP still briefly reachable.

### 2.3 Windows restore does not destroy real `.git` — **PASS**

`scripts/server/claude-mount.sh` `_restore_git_body()` (Windows path):

- Skips when `(Test-Path $p/.git -PathType Container) -and (Test-Path $p/.git/HEAD)` — real repo dir preserved.
- Only `Remove-Item` on `-PathType Leaf` (worktree pointer file), then `Rename-Item .git.server-session → .git`.
- Contract C1 also confirms no `Remove-Item -Recurse` on `.git` anywhere in mount script.

### 2.4 CR strip on conf load — **PASS**

| File | Location |
|------|----------|
| `scripts/server/claude-mount.sh` | `_load_global()`: `v="$(printf '%s' "$v" | tr -d '\r')"` on every conf key including `TUNNEL_PORT`. |
| `scripts/server/claude-watchdog.sh` | `_load_conf()`: same `tr -d '\r'` on parsed values. |

### 2.5 Foreign session: `SS:UNKNOWN` does not auto-clear — **PASS**

Both client guards only auto-clear when `ss` **positively** reports zero listeners (or no port in conf):

| File | Behavior |
|------|----------|
| `scripts/client/git-mode.ps1` `Warn-ForeignServerSession` | On non-numeric `liveRaw`: logs `SS:UNKNOWN … - not clearing connect conf`; auto-clear only if `-not $portDigits -or ($ssOk -and $live -eq 0)`. |
| `scripts/client/git-mode.sh` `warn_foreign_server_session` | Same: logs `SS:UNKNOWN … - not clearing connect conf`; auto-clear only if `[ -z "$existing_port" ] || { [ "$ss_ok" = "1" ] && [ "${live:-0}" = "0" ]; }`. |

When `$ssOk`/`ss_ok` is false, flow falls through to foreign-session prompt (ambiguous = possibly live).

---

## Summary table

| Check | Status |
|-------|--------|
| Contract script run | PASS |
| No alphabetical ACTIVE_MOUNT | PASS |
| Watchdog → `claude-mount down` | PASS |
| Win restore preserves real `.git` | PASS |
| CR strip on conf load | PASS |
| SS:UNKNOWN no auto-clear | PASS |

**OVERALL: PASS** (6/6 contract + 5/5 static)
