# TEST-HARD-6 — Agent T6 Security Verification

**Project:** `claude-code-server` (laptop-exec only, `-p claude-code-server`)  
**Date:** 2026-07-20  
**Scope:** Static security HARD suite + manual static verification  
**Deploy:** None

---

## Overall

**PASS** (6/6 contract checks; all static verifications pass)

---

## 1. Security contract suite

**Script:** `scripts/tmp/test-security-contracts.ps1`  
**Command:** `laptop-exec run -p claude-code-server -- powershell -NoProfile -File scripts/tmp/test-security-contracts.ps1`  
**Exit code:** 0  
**Result:** HARD PASS (0 FAIL / 6 checks)

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Deploy credentials — no hardcoded / `sepidz@Admin` fallback | **PASS** | No hardcoded password; no `sepidz@Admin` missing-file fallback |
| 2 | `add-user.sh` SQL password placeholder only | **PASS** | `"SQLSERVER_PASSWORD": "CHANGE_ME"` |
| 3 | OAUTH token not world-readable in `/etc/environment` | **PASS** | No unprotected `/etc/environment` OAUTH writes |
| 4 | Golden `auth.json` not mode 644 | **PASS** | No 644 install of golden auth.json |
| 5 | Client scripts — no sudo password on cmdline | **PASS** | No sudo password echoed on cmdline |
| 6 | No unrestricted sepidz key merge / NOPASSWD for all keys | **PASS** | No unrestricted all-users key merge; sepidz lacks NOPASSWD |

### Suite machine output

```
[PASS] CHECK 1: deploy credentials no hardcoded/sepidz@Admin fallback
[PASS] CHECK 2: add-user.sh SQL password placeholder only - placeholder OK: CHANGE_ME
[PASS] CHECK 3: OAUTH token not world-readable /etc/environment
[PASS] CHECK 4: golden auth.json not mode 644
[PASS] CHECK 5: client scripts no sudo password on cmdline
[PASS] CHECK 6: no unrestricted sepidz key merge/NOPASSWD for all keys
Overall: HARD PASS (0 FAIL / 6 checks)
```

---

## 2. Static verification (requested items)

### 2.1 Get-DeployCredentials — no `sepidz@Admin` fallback

**File:** `publish/Get-DeployCredentials.ps1`

| Assertion | Result | Evidence |
|-----------|--------|----------|
| No `sepidz@Admin` literal | **PASS** | `laptop-exec rg -p claude-code-server sepidz@Admin .` → no matches |
| Throws when password missing | **PASS** | `Get-SepidzSudoPassword` / `Get-SmartSudoPassword` throw with `No hardcoded fallback is allowed` |
| No return fallback | **PASS** | No `return 'sepidz@Admin'` or similar; only env var → local file → throw |

Credentials load from gitignored `publish/*-deploy.local.ps1` or env vars (`SEPIDZ_SUDO_PASSWORD`, `SMART_SUDO_PASSWORD`).

### 2.2 SQL `CHANGE_ME` in add-user

**File:** `scripts/server/commands/add-user.sh` (settings.json template)

```json
"SQLSERVER_PASSWORD": "CHANGE_ME"
```

**Result:** **PASS** — placeholder only, no real password in template.

### 2.3 Askpass — no password on cmdline

**File:** `scripts/client/git-mode.sh` — `laptop_ssh_bootstrap_local()`

| Assertion | Result | Evidence |
|-----------|--------|----------|
| Password not in askpass argv | **PASS** | Password written to mode-600 secret file (`$secref`); askpass script is `cat <file>` |
| No `echo $PASS \| sudo` | **PASS** | `laptop-exec rg` for `printf 'echo '`, `echo.*LAPTOP_ADMIN`, `echo.*sudo -S` in `scripts/client/` → no matches |
| Comment documents intent | **PASS** | `# Password lives only in mode-600 secret file; askpass argv is "cat <file>" (no pw on cmdline).` |

Implementation:

```sh
printf '%s\n' "$LAPTOP_ADMIN_PW" > "$secref"
chmod 600 "$secref"
{
    printf '#!/bin/sh\n'
    printf 'cat %q\n' "$secref"
} > "$askpass"
chmod 700 "$askpass"
SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force ssh ...
rm -f "$askpass" "$secref"
```

### 2.4 Golden / OAuth chmod patterns (install + refresh)

| File | Pattern | Result |
|------|---------|--------|
| `scripts/server/commands/install.sh` | `chmod 700 /etc/cursor-auth/golden` | **PASS** |
| `scripts/server/commands/install.sh` | `chmod 600 /etc/cursor-auth/golden/*` | **PASS** |
| `scripts/server/commands/install.sh` | `chmod 700 /etc/claude-code` | **PASS** |
| `scripts/server/commands/install.sh` | `chmod 600 /etc/claude-code/oauth.env` | **PASS** |
| `scripts/server/commands/update-server.sh` | `chmod 700 /etc/claude-code` + `chmod 600 oauth.env` | **PASS** |
| `scripts/server/cursor-auth-export.sh` | `chmod 700` golden dir, `chmod 600` golden/* | **PASS** |
| `scripts/server/cursor-auth-refresh.sh` | `atomic_write(..., mode=0o600)` for auth.json, state-keys, exported_at | **PASS** |
| `scripts/server/cursor-auth-refresh.sh` | `os.chmod(mod.GOLDEN_DIR, 0o700)` after refresh | **PASS** |
| `scripts/server/commands/import-cursor-golden-laptop.sh` | `chmod 700` / `chmod 600` golden | **PASS** |
| `scripts/server/commands/diagnose-auth.sh` | Validates oauth.env mode 600 | **PASS** |

No `chmod 644` on golden secret files in install/export/sync paths.

---

## 3. Method

- **Tunnel:** UP (`laptop-exec status`, port 21002, laptop Smart/windows)
- **Active mount:** `ai-gap-summay` (workspace ≠ project → always `-p claude-code-server`)
- **Tools:** laptop-exec read/rg/run/write only; no deploy; no Cursor Read/Grep on `/mounts/`

---

## 4. Residual notes (informational, not failures)

- `publish/sepidz-deploy.local.ps1` / `publish/smart-deploy.local.ps1` may contain real passwords on laptop — expected gitignored local deploy secrets; not hardcoded in committed scripts.
- `scripts/tmp/*` one-off helpers may contain test literals; outside contract scope.
- `CLAUDE.md` documents example SQL credentials for server admin reference; not in `add-user.sh` template.

---

## Artifacts

| Artifact | Path |
|----------|------|
| Contract suite | `scripts/tmp/test-security-contracts.ps1` |
| This report | `scripts/tmp/TEST-HARD-6.md` |
