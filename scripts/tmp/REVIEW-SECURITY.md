# Security review — bugs 1,2,3,4,16–19,54,74

**Date:** 2026-07-20  
**Tree:** laptop `claude-code-server` via `laptop-exec` (no deploy)  
**FIX-AGENT-1.md:** **ABSENT** (only `FIX-PLAN-20260720.md` present; Agent 1 deliverable not filed)  
**Method:** Skeptical re-verify of CURRENT tree; confidence ≥4 only for confirmed issues.  
**Overall:** **FAIL** — several P0 paths fixed, but critical incomplete / unfixed residuals remain.

Legend: **PASS** = exploit path closed in source for that slug. **FAIL** = still exploitable or incomplete in a way that leaves the original bug open. **PARTIAL** = primary path improved; residual exploit / dead-path reintroduction remains.

---

## Executive verdict

| # | Slug | Verdict | Sev (residual) |
|---|------|---------|----------------|
| 1 | `hardcoded-sepidz-sudo-fallback` | **PASS** | — |
| 74 | `hardcoded-sepidz-sudo-in-deploy-bundles` | **PASS** | — |
| 2 | `sepidz-ak-merge-plus-nopasswd-bundle` | **PASS** (code) / **ops residual** | HIGH if live sudoers/AK not redeployed |
| 3 | `shared-oauth-in-etc-environment` | **FAIL** (incomplete) | **CRITICAL** |
| 4 | `sqlserver-password-in-add-user-template` | **PARTIAL** | **HIGH** (docs) / LOW (template) |
| 16 | `always-elevated-connect` | **FAIL** | **HIGH** |
| 17 | `administrators-authorized-keys-server-key` | **FAIL** (mitigated, not fixed) | **MEDIUM** |
| 18 | `cursor-golden-world-readable` | **FAIL** | **CRITICAL** |
| 19 | `secrets-adjacent-logging` | **PARTIAL** | **HIGH** |
| 54 | `world-readable-client-bundle-server-tree` | **PARTIAL** | **MEDIUM** |

**Harsh bottom line:** Agent-1-style edits landed for sudo hardcodes + sepidz AK/NOPASSWD + OAuth primary store, but **did not finish**. `update-server.sh --token` still re-poisons `/etc/environment` with a world-readable OAuth token. Cursor golden `auth.json` is still `644`. Connect still always UAC-elevates. No `FIX-AGENT-1.md`.

---

## 1 / 74 — Hardcoded Sepidz sudo fallbacks

### Verdict: **PASS**

### Proof (rg / Select-String)

```text
ZERO hits in publish/Get-DeployCredentials.ps1 + publish/deploy-client-bundles.ps1
for pattern sepidz@Admin
```

**Get-DeployCredentials.ps1** — missing password now **throws** (no hardcoded return):

```41:46:publish/Get-DeployCredentials.ps1
    throw @"
Sepidz sudo password not found.
Set SEPIDZ_SUDO_PASSWORD or create publish/sepidz-deploy.local.ps1 with:
  `$SepidzSudoPassword = '...'
No hardcoded fallback is allowed.
"@
```

**deploy-client-bundles.ps1** — Sepidz path calls `Get-SepidzSudoPassword` only; prior `if (-not $sudoPw) { $sudoPw = 'sepidz@Admin' }` is **gone**:

```294:295:publish/deploy-client-bundles.ps1
            # Fail loudly if publish/sepidz-deploy.local.ps1 (or env) is missing — no hardcoded fallback.
            $sudoPw = Get-SepidzSudoPassword
```

### Residuals (not slug FAIL, but harsh notes)

| Residual | Evidence | Sev |
|----------|----------|-----|
| Real password still in **gitignored** `publish/sepidz-deploy.local.ps1` | Select-String hit: `$SepidzSudoPassword = 'sepidz@Admin'` | Expected for local deploy; ensure never committed |
| Dozens of `scripts/tmp/*` still embed `sepidz@Admin` in SSH/sudo one-liners | `_sec-scan` hit list (fleet-scan, deep-pull*, sepidz-*.sh, …) | **HIGH** if `scripts/tmp` is shared/copied; `.gitignore` only has `.tmp/` — **`scripts/tmp` is NOT ignored** |
| Historical “check that hardcode exists” tests under `scripts/tmp/check_pw.ps1` etc. | Still assert for hardcoded return | Noise / can reintroduce confusion |

---

## 2 — sepidz AK merge + NOPASSWD → root via any laptop key

### Verdict: **PASS** in source (combo broken). **Ops residual HIGH** until servers redeployed / AK cleaned.

### Evidence — merge removed

**add-user.sh** (was merging user keys into `/home/sepidz/.ssh/authorized_keys`):

```261:262:scripts/server/commands/add-user.sh
# SECURITY: do not merge this user's keys into sepidz authorized_keys.
# Auto-update uses the developer's own REMOTE_USER account (connect-update.*).
```

**deploy-client-bundle.sh** — `_sync_sepidz_update_keys` removed; explicit ban:

```237:241:scripts/server/commands/deploy-client-bundle.sh
# SECURITY: do NOT merge developer authorized_keys into sepidz. That plus
# NOPASSWD install-client-bundle allowed any laptop key to root-install.
# Clients pull the bundle as their own REMOTE_USER (see connect-update.*).
# server/ scripts are not needed for laptop auto-update apply paths — drop
# them from the world-readable share (keep win/mac client files only).
```

### Evidence — sepidz NOPASSWD removed

**scripts/server/sudoers.d/claude-client-deploy** (full file, 9 lines):

- Comment documents why sepidz must NOT have NOPASSWD.
- Only: `smart ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE`
- **No** `sepidz ALL=(root) NOPASSWD:…`
- **No** `Defaults:sepidz !requiretty`

### Remaining exploit paths

| Path | Status | Sev | Conf |
|------|--------|-----|------|
| New merge + new NOPASSWD on next `install` from this tree | Closed in source | — | 5 |
| **Live Sepidz** still has old `/etc/sudoers.d/claude-client-deploy` until deploy | **Still exploitable on disk** if not redeployed (review scope = code; flag anyway) | CRITICAL→ops | 4 |
| **Stale keys already in** `/home/sepidz/.ssh/authorized_keys` | Code no longer adds; does not purge historical keys | HIGH | 5 |
| `smart` NOPASSWD bundle install | Intentional deploy path; compromise of smart key = root install of client bundle | MEDIUM (accepted?) | 5 |
| Password sudo via `deploy-client-bundles` still embeds base64 password in remote wrap script | See #19 | HIGH | 5 |

---

## 3 — OAuth in world-readable `/etc/environment`

### Verdict: **FAIL** — primary path fixed; **reintroduction path still live**

### What improved (not enough)

**claude-auth-lib.py** — root-only store + strip legacy:

```17:20:scripts/server/claude-auth-lib.py
AUTH_LOG = Path("/var/log/claude-auth.log")
# Root-only token store (mode 0600). Legacy /etc/environment is migrated away.
TOKEN_FILE = Path("/etc/claude-code/oauth.env")
ENV_FILE = Path("/etc/environment")  # legacy; token stripped on deploy
```

```175:183:scripts/server/claude-auth-lib.py
def write_env_token(token: str) -> None:
    """Write token to root-only /etc/claude-code/oauth.env; strip legacy world-readable copies."""
    ...
    os.chmod(TOKEN_FILE, 0o600)
    # Remove world-readable copies (historical /etc/environment mode 644).
    _strip_token_from_file(ENV_FILE)
```

**deploy-auth.sh** message claims oauth.env 0600 + strip (wired through lib).  
**install.sh** “Next steps” now points at `deploy-auth` / oauth.env (no longer tells admins to append `/etc/environment` in the success banner).  
**claude-auth-sync.sh** prefers `/etc/claude-code/oauth.env`, falls back to `/etc/environment`.

### Confirmed remaining exploit — `update-server.sh --token`

```90:95:scripts/server/commands/update-server.sh
    echo "export CLAUDE_CODE_OAUTH_TOKEN=$NEW_TOKEN" > /etc/profile.d/claude-auth.sh
    chmod 644 /etc/profile.d/claude-auth.sh
    grep -v '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment > /tmp/claude-env.$$
    mv /tmp/claude-env.$$ /etc/environment
    echo "CLAUDE_CODE_OAUTH_TOKEN=$NEW_TOKEN" >> /etc/environment
    ok "token updated in profile.d + /etc/environment"
```

This **re-writes the full OAuth token** into:

1. `/etc/profile.d/claude-auth.sh` mode **644** (world-readable export)
2. `/etc/environment` (typically **644**)

Any local user can read it. This is the original bug class, still live. **Incomplete fix that looks fixed if you only read `claude-auth-lib.py`.**

| Also | Evidence | Sev |
|------|----------|-----|
| Per-user `~/.claude/settings.json` still receives full token via sync | By design for VS Code; mitigated by `chmod 700` home in add-user | MEDIUM if home perms regress |
| `settings.json` not explicitly `chmod 600` (only credentials.json is) | `claude-auth-sync.sh` chmod 600 only on `.credentials.json` | LOW given home 700 |

**Conf:** 5

---

## 4 — SQL password in add-user template

### Verdict: **PARTIAL**

| Location | Status | Evidence |
|----------|--------|----------|
| `scripts/server/commands/add-user.sh` template | **Fixed** (placeholder) | `"SQLSERVER_PASSWORD": "CHANGE_ME"` (~L175) |
| `CLAUDE.md` | **NOT fixed** | L148 still `"SQLSERVER_PASSWORD": "Mohammad123"` |

Real password removed from the provisioning template → new users no longer get the production SQL password baked in. **Docs still leak the historical password** (and teach copy-paste of a real secret).

**Conf:** 5 for CLAUDE.md residual; 5 that template no longer embeds `Mohammad123`.

---

## 16 — Always-elevated connect (Windows)

### Verdict: **FAIL**

```26:40:scripts/client/windows/connect.ps1
# Always run elevated (sshd, firewall, administrators_authorized_keys need admin).
if (-not $AdminFix) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        ...
            Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs -ErrorAction Stop | Out-Null
```

Entire session still forces Admin. CLAUDE.md invariant still claims “No unconditional RunAs… Use `-AdminFix`” — **docs/code lie** relative to this block.

**Exploit/impact:** Full connect attack surface runs elevated for hours; any connect RCE/path bug = Admin.  
**Conf:** 5

---

## 17 — Server key in `administrators_authorized_keys`

### Verdict: **FAIL** (mitigated, not remediated)

Still installs server pubkey into admin AK with `from=` restriction:

```261:265:scripts/client/windows/connect.ps1
        # Remove any existing entry for this key (restricted or not), then add with from= restriction
        $restricted = "from=`"127.0.0.1,::1,localhost,::ffff:127.0.0.1`" $pub"
        $lines = @($lines | Where-Object { $_ -notlike "*$pub*" })
        $lines += $restricted
        Set-Content -Path $akFile -Value $lines -Encoding ASCII
```

`from=loopback` blocks remote WAN abuse; **does not** remove the trust that anything able to hit laptop sshd via the reverse tunnel (server-side) can authenticate as a Windows admin-equivalent SSH principal.

Designer fork uses a slightly narrower `from="127.0.0.1,::1"` (no localhost aliases) — parity nit only.

**Conf:** 5 that behavior unchanged; severity MEDIUM given from= mitigation.

---

## 18 — Cursor golden world-readable

### Verdict: **FAIL** — **CRITICAL**

Still explicitly world-readable:

| File | Lines | Mode |
|------|-------|------|
| `scripts/server/cursor-auth-export.sh` | 109–110 | `chmod 755` dir; `chmod 644` golden/* |
| `scripts/server/commands/import-cursor-golden-laptop.sh` | 55–56 | same |
| `scripts/server/cursor-auth-lib.py` | ~293–298 | `atomic_write(..., mode=0o644)` for `auth.json`, state-keys, storage, machine-id |
| `scripts/server/commands/install.sh` | 296 | `chmod 755 /etc/cursor-auth/golden` |

`auth.json` holds access + refresh tokens. Any server account can read `/etc/cursor-auth/golden/auth.json` and hijack the shared Cursor identity.

**No evidence of a real chmod 600/640 + group restriction fix.** Comments elsewhere about “same trust model as /etc/environment” are rationalization, not remediation.

**Conf:** 5

---

## 19 — Secrets-adjacent logging / cmdline leakage

### Verdict: **PARTIAL**

### Improved

- `token_fingerprint()` now returns `{len, sha256[:16], present}` — no raw token / prefix bytes (`claude-auth-lib.py` L31–36).
- Lib forces `/var/log/claude-auth.log` to **0600** on append (L77–84).

### Still open

| Issue | Evidence | Sev | Conf |
|-------|----------|-----|------|
| `install.sh` creates auth log as **644** | L110–111 `touch` + `chmod 644 /var/log/claude-auth.log` | MEDIUM (race / until first lib write) | 5 |
| Cron redirects may recreate/append as root with inherited mode | install L118 `>> /var/log/claude-auth.log` | LOW–MED | 4 |
| **Sudo password in remote install wrap** as base64 in script body | `deploy-client-bundles.ps1` L217–221 `PW=$(echo {b64} \| base64 -d)` written to `/tmp/remote-install-$Label.sh` on target | **HIGH** (readable by target user; briefly on disk) | 5 |
| `sudo-from-laptop.sh` can pass password via `echo '…' \| sudo -S` in remote cmdline | L127 pattern in scan | HIGH (process list / shell history on laptop SSH hop) | 4 |
| Fingerprints still in world-readable logs if chmod 644 wins | diagnose-auth prints fingerprints to stdout; install 644 | LOW (sha256 trunc not secret alone) | 4 |
| `scripts/tmp/**` plaintext `sepidz@Admin` sprawl | See #1 residuals | HIGH if tree shared | 5 |

Original “diagnose pulls private key” — **not confirmed** in current `diagnose-auth.sh` (no private key cat found). Do not allege without evidence.

---

## 54 — World-readable client bundle includes server tree

### Verdict: **PARTIAL**

### Improved

Both install paths **delete `server/` after install** and strip `server/` from manifest:

- `deploy-client-bundle.sh` L242–251 `rm -rf "$BUNDLE_ROOT/server"`
- `install-client-bundle.sh` L124–132 same

### Incomplete / residual exploit window

| Issue | Evidence | Sev | Conf |
|-------|----------|-----|------|
| Publish still **packages** `ServerBundleFiles` into the zip | `publish/deploy-client-bundles.ps1` L50–58 | MEDIUM | 5 |
| Install still **extracts** `server/` then removes — TOCTOU world-readable window | install-client-bundle chmod 755/644 on server tree **before** rm | MEDIUM | 5 |
| Deploy dir zip `~/claude-client-bundle-deploy/bundle.zip` may retain full server tree for account owner | upload path in deploy-client-bundles | LOW–MED | 4 |
| Final share still **755/644** for all client scripts (intentional; no secrets claimed) | find chmod 755/644 | OK if no secrets | 5 |

Looks “fixed” in comments; packaging + staging still ship server scripts into a world-readable tree before deletion.

---

## FIX-AGENT-1.md

**ABSENT.** Plan assigns Agent 1 these slugs; no deliverable report under `scripts/tmp/FIX-AGENT-1.md`. Treat unfixed/partial items as unacknowledged by the fix agent.

---

## Priority remediations (code-only; no deploy performed)

1. **CRITICAL:** Rewrite `update-server.sh --token` to call `claude-auth-lib.py deploy` / `write_env_token` + `write_profile_token` — never write token to `/etc/environment` or profile.d.  
2. **CRITICAL:** Golden Cursor files → `0640` root:cursor-auth (or root-only `0600` + root-only sync helper); stop `chmod 644` in export/import/lib.  
3. **HIGH:** Rotate Sepidz sudo password (was in hardcode + tmp scripts + local file); scrub `scripts/tmp` secrets or gitignore `scripts/tmp/`.  
4. **HIGH:** On Sepidz (ops): replace sudoers from new tree; audit/purge merged keys in `sepidz` authorized_keys.  
5. **HIGH:** Connect: elevate only for `Ensure-LaptopSshReady` / AdminFix, not whole session (#16).  
6. **HIGH:** Stop embedding sudo password base64 in remote wrap files; use `sudo -S` over SSH stdin only, shred remote wrap.  
7. **MED:** Remove `ServerBundleFiles` from publish zip entirely if clients never apply `server/*`.  
8. **MED:** Replace `Mohammad123` in `CLAUDE.md` with `CHANGE_ME` / env docs.  
9. **MED:** `chmod 600` on `/var/log/claude-auth.log` in install.sh (match lib).  
10. File `scripts/tmp/FIX-AGENT-1.md` with honest PASS/FAIL — currently missing.

---

## Confidence summary

| Claim | Conf |
|-------|------|
| sepidz@Admin gone from Get-DeployCredentials + deploy-client-bundles | **5** |
| sepidz NOPASSWD + AK merge removed in source | **5** |
| update-server.sh still writes OAuth to world-readable paths | **5** |
| golden auth.json still 644 | **5** |
| connect still always RunAs | **5** |
| SQL real password gone from add-user, remains in CLAUDE.md | **5** |
| Live server still exploitable without redeploy | **4** (ops, not proven this run) |
| diagnose pulls private key | **not confirmed** — dropped |

**Reviewer disposition: FAIL overall for Agent-1 security scope.**
