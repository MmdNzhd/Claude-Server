# Task 8 Report — Deploy + Gap replay (ship gate D10)

**STATUS:** DONE  
**D10:** **PASS** (Step 2b harness; live dual-UI skipped with documented mitigation)  
**Deploy:** `publish\deploy-scripts-only.ps1` (no `-SkipTests`) → **exit 0**  
**Log:** `publish/_task8-deploy.log`

---

## Step 0 — Zombie owner ops note

At Task 8 start, `%USERPROFILE%\.config\claude-connect\cursor-proxy-owner.json` held:

```json
{"pid":54996,"slot":1,"socks":19080,"http":19180,"started_utc":"2026-07-29T12:09:59.8047658Z"}
```

| Check | Result |
|---|---|
| pid 54996 alive? | **Yes** (powershell; session `c25e36b2831c`) |
| backends 19080/19180 | **Down** |
| fronts 18998/18999 | **Down** |
| Second Connect | pid 2084 `connect-boot.ps1` (session `a3deba379fd2`) still active |

**Mitigation (do not force-kill blindly):** Close the zombie owner Connect window (session `c25e36b2831c` / pid **54996**) so the owner lease can clear or be adopted. Do **not** kill unrelated Connect/Cursor work (e.g. pid 2084) without checking. Live dual-UI Gap replay was skipped because that lease was still held; Step **2b harness** satisfies D10 instead.

---

## Step 1 — Deploy

| Item | Value |
|---|---|
| Command | `powershell -NoProfile -ExecutionPolicy Bypass -File publish\deploy-scripts-only.ps1` |
| `-SkipTests` | **Not used** |
| Version bump | `20260729.14` → **`20260729.15`** |
| Deploy-gate | **Passed: 130 / Failed: 0** |
| Remote bundle | `/usr/local/share/claude-client` v**20260729.15** |
| Policy `latest` | **`20260729.15`** (matches) |
| EXE | Unchanged md5 `26f8003b29e97b2390e665f4fc43a445` (scripts-only; no invented SFX) |
| Deploy exit | **0** |

---

## Step 2b — Harness Gap replay (S6 A–E)

**Suite:** `scripts/client/tests/test-incident-gap-replay-harness.ps1` (registered in `run-all.ps1`)  
**Transcript:** `.superpowers/sdd/briefs/task-8-gap-replay-transcript.txt`  
**Harness exit:** **0** (21 asserts)

### Quoted S6 evidence (from transcript)

**A — `foreign_owner_cannot_bind` (Ensure + bg_init):**
```
GITMODE: ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind pid=424242 port=20021
ENSURE_TUNNEL bg_init_reseed_skip reason=foreign_owner_cannot_bind pid=424242 port=20021
```

**B — zero `killing stale bg` for that Gap skip:**
- Behavioral: `kill_count=0`; Gap segment has no `killing stale bg` line.
- Transcript Gap A/B lines are only `reused=1` + `reseed_skip reason=foreign_owner_cannot_bind`.

**C — still-busy refuse + Wait `local_r_not_owned` (no false `TUNNEL_WAIT ok=1`):**
```
GITMODE: ENSURE_TUNNEL refuse_spawn reason=stale_port_busy port=20021
GITMODE: TUNNEL_WAIT ok=0 attempt=1 reason=local_r_not_owned port=20021 pid=... local_pids=
GITMODE: TUNNEL_WAIT fail=1 reason=local_r_not_owned port=20021 pid=...
```

**D — `released reason=service_dead` at 60s:**
```
GITMODE: CURSOR_PROXY_OWNER: service_dead age_sec=60 threshold=60
GITMODE: CURSOR_PROXY_OWNER: released reason=service_dead pid=...
```

**E — healthy control still logs `proxy_leg=-L`:**
```
GITMODE: ENSURE_TUNNEL proxy_leg=-L local=19080 remote=10808
GITMODE: ENSURE_TUNNEL proxy_leg=-L local=19080 remote=1080 healthy_control=1
```

---

## Step 3 — Rollback

Redeploy previous scripts-only version without inventing EXE:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File publish\deploy-scripts-only.ps1 -NoBump -Version 20260729.14
```

(Or set repo connect-version files back to `20260729.14` and re-run scripts-only with `-NoBump`.) EXE hash stays the prior IExpress payload; full SFX rebuild remains `publish\publish.bat` only when needed.

---

## Files (this task)

| File | Change |
|---|---|
| `scripts/client/tests/test-incident-gap-replay-harness.ps1` | **New** Step 2b S6 A–E harness |
| `scripts/client/tests/run-all.ps1` | Register harness |
| `.superpowers/sdd/briefs/task-8-gap-replay-transcript.txt` | Harness transcript |
| Version files + `client-update-policy.json` | Bumped to **20260729.15** by deploy |
| `publish/_task8-deploy.log` | Deploy tee log |

**D10 gate result:** **PASS**
