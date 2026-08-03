# Cursor shared-account rotation (Smart / Sepidz)

Goal: change the fleet Cursor login in **minutes**, not hours.
Chat uses the **laptop** profile (`%LOCALAPPDATA%\ClaudeServerCursorProfile-Smart`), not only server `~/.config/Cursor`.

## Preconditions (client already fixed)

Require Connect **>= 20260803.3** (force policy ships this):

| Bug that burned time | Fix in client |
|---|---|
| Stamp `local_ttl` faked "current" for 60 min after golden change | Stamp compares real server `exported-at` (session_cache only) |
| Huge `state.vscdb` → `db_too_large` skip forever | Bypass size gate when golden is stale / Force |
| Settings still showed old nickname | Merge clears `cursor.customize.userDisplayNameCache` |
| Server sync OK but laptop still old | Connect merges laptop DB on every golden_stale |

If fleet is older: bump `client-update-policy.json` to `mode=force` + new `latest`, deploy bundle, then rotate.

## Rotate (happy path)

1. **Login once on server** as `smart` (or bootstrap user):
   ```bash
   # Remote SSH [Claude Server] window, or:
   agent login
   ```
   Confirm `agent status` shows the **new** email.

2. **Export golden** (personal-email denylist may need override):
   ```bash
   sudo-from-laptop --smart -- cursor-auth-export --from-user smart --allow-personal
   # or: sudo cursor-auth-export --from-user smart --allow-personal
   ```

3. **Bump stamp** so every laptop must re-merge (even if tokens look "complete"):
   ```bash
   sudo-from-laptop --smart -- bash -lc \
     'date -u +%Y-%m-%dT%H:%M:%SZ > /etc/cursor-auth/golden/exported-at'
   ```

4. **Sync server homes**:
   ```bash
   sudo-from-laptop --smart -- claude-server sync-cursor-auth
   # fallback if wrapper missing:
   # sudo-from-laptop --smart -- bash /usr/local/lib/claude-server/sync-cursor-auth.sh
   ```

5. **Force client update** (if not already on fixed version):
   - Set `scripts/server/client-update-policy.json` → `mode=force`, `force_min_version` = `latest`
   - Deploy to `/usr/local/share/claude-client/`

6. **Tell fleet**: open Connect (or press **R**). Wait for `Syncing Cursor auth` ok → **Reload Window** in `[Claude Server]`.

7. **Verify** (do not stop at server-only):
   ```bash
   # Server homes must match golden email (DRIFT=0)
   sudo-from-laptop --smart -- python3 - <<'PY'
   import json, sqlite3
   from pathlib import Path
   g = json.loads(Path('/etc/cursor-auth/golden/auth.json').read_text())
   email = g.get('cursorAuth/cachedEmail') or g.get('cachedEmail')
   exp = Path('/etc/cursor-auth/golden/exported-at').read_text().strip()
   print('GOLDEN', email, exp)
   drift = 0
   for home in sorted(Path('/home').iterdir()):
       db = home / '.config/Cursor/User/globalStorage/state.vscdb'
       if not db.exists():
           continue
       c = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
       row = c.execute("select value from ItemTable where key='cursorAuth/cachedEmail'").fetchone()
       c.close()
       e = row[0] if row else None
       ok = e == email
       print(('OK' if ok else 'DRIFT'), home.name, e)
       drift += 0 if ok else 1
   print('DRIFT', drift)
   PY
   ```
   Live laptops: Connect log must show merge or stamp match to **new** `exported-at`. Spot-check:
   `%LOCALAPPDATA%\ClaudeServerCursorProfile-Smart\User\globalStorage\golden-synced-at.txt`

## If one laptop still shows the old account

| Check | Action |
|---|---|
| Connect version &lt; fixed | Force update / copy bundle |
| `AUTH_SYNC_SKIP db_too_large` on **old** client | Close `[Claude Server]`, prune/wipe profile DB, reconnect (new client bypasses on rotation) |
| Stamp file equals old export | Press **R** or **P** after bumping `exported-at` |
| Email OK but UI name old | Reload Window (display cache cleared on merge in new client) |
| Chat dead in **one** project window only | Same auth for all windows — Reload that window; not an account drift |

## Do NOT

- Stop after `sync-cursor-auth` alone (Chat is laptop-profile).
- Trust "Settings shows Ashkin" without reading `cursorAuth/cachedEmail` in the laptop DB.
- Blame shared-account `past_due` before confirming laptop email == golden (old ashkin laptops looked "fine" while new golden looked past_due).
- Re-derive infra from scratch — follow this file.

## Related

- Pilot checklist: [`scripts/server/CURSOR-AUTH-PILOT.md`](../scripts/server/CURSOR-AUTH-PILOT.md)
- Connect auth behavior: [`docs/client-connect.md`](client-connect.md) (Cursor profiles)
