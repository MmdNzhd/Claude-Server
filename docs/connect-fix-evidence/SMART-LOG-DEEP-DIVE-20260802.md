# Smart laptop connect-log deep dive — 2026-08-02

Unified master report from Smart day logs, live server probes, Desktop / repo / share comparison, and five parallel investigate agents. **Investigation only — no fixes applied.**

**Scope:** Smart laptop only (not Sepidz; not full-fleet remediation). Corrects several attributions in [`FLEET-PROBLEMS-20260801.md`](FLEET-PROBLEMS-20260801.md) for Smart specifically.

---

## 1. Sources and agents

| Artifact | Path |
|---|---|
| Laptop day logs | `%USERPROFILE%\.config\claude-connect\logs\connect-2026080{1,2}.log` |
| Sync watermark / pending | same dir: `*.sync-offset`, `*.sync-pending` |
| Server day logs | `/home/smart/.claude/logs/connect-2026080{1,2}.log` |
| Server share | `/usr/local/share/claude-client` (`20260801.10`) |
| Desktop install | `Desktop\Claude-Connect\20260801.10\src` (+ older `20260801.9` etc.) |
| Repo | `D:\Smart\Claude-Code-Server\scripts\client\…` |
| Prior fleet inventory | [`FLEET-PROBLEMS-20260801.md`](FLEET-PROBLEMS-20260801.md) |
| Zombie-forward design note | `docs/superpowers/plans/2026-07-29-zombie-owner-reseed-tunnel-ready.md` |

| Domain | Agent | Focus |
|---|---|---|
| Tunnel / SSH | [Tunnel/SSH](3c9fbd84-88ed-4981-9399-b43c127ecdea) | Unknown-error storm, STALE_FORWARD deadlock, PUSH_CONF |
| Log sync | [Log sync](ad96180e-ff7a-47c3-a2f8-0fbaeed9238e) | mkdir/scp/nullref, watermark delivery |
| Cursor launch + auth | [Cursor launch+auth](0c8674d4-fbff-427d-9b77-4633f6cabbca) | false "elevated fail", strategy order, db_too_large |
| Update / proxy / WMCP | [Update/proxy](4050650f-fff0-427a-a377-241d4e2fdd8d) | checksum race, System32 promote, xray, WMCP |
| Mutex / Trim crashes | [Mutex/Trim](c3e0962a-bcb9-4049-9449-d025478853eb) | split-generation bundle, Object[].Trim |

---

## 2. Executive summary

1. **Aug 1 pain was dominated by one session** (`23f2a722cf0d`, Connect `20260801.01`, port **20020**): ~6 min network-loss storm (Incident A) + ~13 min **zombie-forward self-deadlock** (Incident B: `refuse_spawn` reads a marker it wrote ~1.7s earlier). Dual Connect (`3469e31724f7` on **20021**) started **~6 min into Incident B** — workaround, not trigger.
2. **Many ERROR/WARN counts are inflated** by hard/stress tests (slots 0–9, `vstress` log-sync harness) and by false-positive UX ("elevated launch failed" while `elevated=False`).
3. **Aug 2 Connect session is tunnel-healthy** (zero storm markers) but still has: slow Cursor open (~40s, 3 orphan PIDs), morning update checksum race, and **silent log-sync starvation** (watermark **0** — local truth not shipped). Quiet Aug 2 is **not proof the tunnel bugs were fixed** — last `git-mode.ps1` commit touching those paths is still `1ed3939` (2026-07-29); defects are latent.
4. **Several real fixes exist only in the uncommitted working tree** / Desktop `20260801.10\src` and are **not** in git HEAD; version string `20260801.10` has covered multiple distinct contents.
5. **Live during investigation:** server load spiked ~20–55 (I/O wait); Amir had `git status` stuck in **D-state** on sshfs `smartclub` — fleet-visible, separate from Smart's Connect session.

---

## 3. Log inventory (Smart)

### 3.1 Aggregates — 2026-08-01 (~967 ERROR/WARN lines)

| Pattern | Approx count | Real pain? |
|---|---|---|
| `ssh: Unknown error` → `:22` | 233 WARN (**466** incl. TRACE/DEBUG for storm session) | Yes — **one session** |
| `STALE_FORWARD` (all forms) | **108** (storm session) | Yes — Incident A/B |
| `LOG_SYNC_FAIL mkdir_timeout_or_fail` | 115 | Mixed — ~195 of hour-22 from stress |
| `LOG_SYNC_FAIL scp_or_append_fail` | 89 | Mixed |
| `LOG_SYNC_FAIL` nullref (bare message) | 17 | Yes — pre-fix builds |
| `PUSH_CONF port_mismatch_keep` | 33+ | Mostly slot≥1 by design / tests |
| `PUSH_CONF fail` | 26 (22 in storm session) | Storm |
| `TUNNEL_WAIT ssh_died` | 24 | Storm |
| `PROXY_FALLBACK xray_closed` | 24 | Incident A only; ForceProbe since shipped |
| `ENSURE_TUNNEL wait_timeout_budget_exhausted` | 18 | Storm |
| `STALE_FORWARD` busy / zombie (subset) | 13+13 | Incident B deadlock |
| `ENSURE_TUNNEL refuse_spawn stale_port_busy` | 12 | Deadlock |
| `elevated launch failed` | 11 | **False alarm** (predicate mismatch) |
| `EDITOR_LAUNCH skip_auth_relaunch` / `RECOVERY_SKIP_CLEAR_MOUNT` | 12+12 | Warm preserve path |
| `.ssh\config` in use by another process | 4–6 | Multi-writer; mutex fix later |
| `CONNECT_AUTH_NEEDED` / `CONNECT_AUTH_VERIFY` | 5+4 | Same multi-Connect race as config lock |
| Other (`MOUNT_BG_FAIL`, `AGENT_PATH`, `golden_stale`, …) | low | Sporadic |

### 3.2 Aggregates — 2026-08-02 (12 ERROR/WARN)

| Pattern | Count | Notes |
|---|---|---|
| `LIVE_*_PROBE` | 6 | Test-only (`test-harder-live-log-flush.ps1`) |
| `UPDATE checksum_fail` / `checksum_verify_failed` | 2 | Bundle inconsistent at 12:25 |
| `UPDATE local_exe_drift` | 1 | `hardprom*` / expected after publish |
| `LAUNCH_RETRY` (remote / classic / folder-uri) | 3 | Recovered on attempt 4 |

### 3.3 Aug 1 session inventory (33k+ lines)

| Session | Window | Notes |
|---|---|---|
| `b4a55da2bd72` | 00:00–11:49 | **Zero** tunnel storm markers |
| `23f2a722cf0d` | 13:21–20:52 | **All** Unknown-error / STALE / refuse_spawn / wait_timeout |
| `3469e31724f7` | 17:04–20:52 | Dual Connect workaround; 9 clean auto-reconnects; `port_mismatch_keep` |
| ~18 short sessions | 20:52–22:05 | Fleet / multi-instance regression (slots 0–9) |
| `f91322b6e9cd` (`vstress`) | ~22:47 | Log-sync stress harness — ~195 FAIL lines |

### 3.4 Noise to exclude from pain metrics

- `LIVE_ERROR_PROBE` / `LIVE_WARN_PROBE` (only producer: `test-harder-live-log-flush.ps1`)
- Most hour-22 `LOG_SYNC_FAIL` (`vstress` / `f91322b6e9cd`)
- Slot 2–9 `PUSH_CONF port_mismatch_keep` + `ACTIVE_MOUNT mismatch` during multi-instance hard tests (`ACTIVE_MOUNT_GUARD … reason=other_still_mounted` behaving as designed)
- `hardprom*` `local_exe_drift` / promote paths (`test-exe-promote-launch-dir-hard.ps1`)

Honest LOG_SYNC read for Aug 1: roughly **~27 genuinely affected sessions + one stress run (~195)**.

---

## 4. Storm timeline — session `23f2a722cf0d` (complete)

**Identity:** v`20260801.01`, project `refactoreoldclub`, **slot 0 / port 20020** for the whole session. Setup from SFX (`IXP000.TMP`), package lineage included older trees. Healthy boot → `CURSOR_ON_FOLDER_OK` by ~13:23. Healthy ~13:23–14:58 (~95 min).

### 4.1 Incident A — 14:58:05 → 15:04:15 (~6m10s) — network-loss class

```
14:58:05  TUNNEL_EXIT pid=… port=20020 exit_code=255 reason=sync_observed_exit
14:58:27  banner exchange: Connection to UNKNOWN port -1: Connection timed out (~21s)
14:58:31  ssh: connect to host 192.168.210.240 port 22: Unknown error  (ms=66–130 typical)
14:58:44  TUNNEL_DROP reason=auto_reconnect sync_fail=3 tcp_open=False
14:58:51  ENSURE_TUNNEL remote_xray_socks=closed port=10808 → PROXY_FALLBACK server_direct
14:58:52  STALE_FORWARD: foreign banner … banner=<Unknown error text>
15:00:50  ENSURE_TUNNEL wait_timeout_budget_exhausted surfacing_ui
```

- Loop `iter=2` → `iter=24`; peak **~116 Unknown error/min** at 15:01.
- Contains vast majority of Unknown-error lines, all 18 `wait_timeout_budget_exhausted`, 22/24 `TUNNEL_WAIT fail`, 22/26 `PUSH_CONF fail`.
- Self-recovered ~15:04. Brief second drop ~15:18.
- **Trigger is laptop-side path loss**, not sshd MaxStartups: instant `connect()` fail (ms=66–130), xray 10808 unreachable same second, **no second Smart Connect at 14:58**. Contradicts fleet doc §P1.1 for Smart.

### 4.2 Incident B — 16:57:16 → 17:10:28 (~13m13s) — zombie-forward deadlock

```
16:57:16  TUNNEL_EXIT / TUNNEL_DROP
16:57:32  ENSURE_TUNNEL spawned … then TUNNEL_WAIT ssh_died
16:58:02  Connection timed out during banner exchange … 127.0.0.1:20020  (signature flips to zombie)
16:58:12  STALE_FORWARD: zombie port=20020 tcp=open banner=(empty)
16:58:53  STALE_FORWARD: port still busy …   ← WRITES marker
16:58:55  ENSURE_TUNNEL refuse_spawn stale_port_busy  ← READS marker (~1.7s later)
… twelve refuse_spawn cycles ~60s apart, ZERO spawns …
17:10:27  ENSURE_TUNNEL skip_release_stale (server reaped)
17:10:28  TUNNEL_UP port=20020
```

### 4.3 Dual Connect — consequence of Incident B

| Time | Event |
|---|---|
| 16:57:16 | Incident B begins |
| 16:58:55 | First `refuse_spawn` — recovery impossible without rebind |
| **17:04:44** | Second Connect `3469e31724f7` slot 1 |
| 17:05:38 | Up on **20021** in ~54s |
| 17:10:28 | Original recovers on 20020 |
| 17:05–20:52 | Both coexist; slot 1 logs `port_mismatch_keep` (dead 20020 stays published) |
| 20:52 | Both killed together |

Slot 1 held the only working tunnel for ~3h47m but `am_only=1` forbade publishing → server conf stayed on dead **20020**.

---

## 5. P0 — Still active (code)

### P0.1 Zombie-forward self-deadlock (`refuse_spawn`) — CRITICAL

**What:** Same `Ensure-SessionTunnel` pass writes `LastStaleForwardStillBusy*` then aborts spawn via `Test-StaleForwardStillBusyAbort` (15s window). Marker renewed every cycle → window never expires. Design comment / plan require **refuse OR rebind** to next slot — only refuse implemented. No streak cap (unlike wait-timeout path). Escape only when server sshd reaps (~12 min).

**Where:** `git-mode.ps1` ~548–601, ~3613–3617. Introduced `405b4c1` (2026-07-29); sibling `91bda73` made wait fail-closed and increased how often release runs.

**Status:** **STILL ACTIVE** (Aug 2 never armed the marker).

### P0.2 Transport error misclassified as "foreign banner" — HIGH

**What:** `Get-TunnelBanner` runs SSH to server then `nc` to the reverse port. When SSH itself fails, stderr text is non-empty and fails `Test-TunnelBannerIsWindows` (`^SSH-2.0-` + `OpenSSH_for_Windows`) → foreign-banner → `Clear-ServerStaleTunnelForward` / `fuser -k` over a dead link (**36 cycles** in Incident A). No error-string guard.

**Where:** `git-mode.ps1` ~267, ~308, ~619–623.

**Status:** **STILL ACTIVE**.

### P0.3 Retry fan-out + inverted backoff — HIGH

| Amplifier | Effect |
|---|---|
| Positive-only banner cache | Failures never cached |
| `Test-TunnelUp` attempts=3 | ×3 |
| Soft-fail sync then TCP | more probes |
| Drop needs sync_fail≥3 | delayed |
| `Wait-ForTunnelUp` i=1..12 | up to ×36 |
| Both wait exits call `Release-StaleTunnelPort` | more clears |
| At streak≥6 backoff sleep **skipped** | flat ~6.5s cadence |

One dead link → ~50 SSH attempts/iteration × ~23 iters ≈ **466** failures in ~6 min.

**Also:** `Unknown error` is in neither `SshX` downgrade nor escalate regex (`connect.ps1` ~1306–1322) → stays WARN, no Force-sync / circuit breaker.

**Status:** **STILL ACTIVE**.

### P0.4 Launch success predicates disagree — HIGH (false UX)

**What:**

1. `Launch-RemoteEditor` returns true on `window_count_increased_no_title_match`.
2. `Confirm-RemoteEditorLaunchVisible` accepts **only** on-folder → StepFail.
3. Message hardcodes **"elevated"** though all 11 runs logged `elevated=False` and tells user to try non-elevated Connect they were already on.

**Warm handoff:** exactly one strategy (`remote`) — same weak signal; no cascade (by design comment "do NOT cascade").

**Cold Aug 2:** strategies `remote` → `remote-classic` → `folder-uri` → **`folder-uri-classic` OK** at 12:53:06 (~39.6s). Comment block claiming `--remote` works cold/warm is **wrong for Cursor 3.13.10**. `LAUNCH_RETRY_NO_KILL` left orphan PIDs **46308, 51632, 64452**.

**Where:** `editor-launch.ps1` ~1006–1013, ~2093–2126, ~2634–2637, ~2740–2745; `connect.ps1` ~3072–3074 / ~3408–3410.

**Proof (Aug 1):** `LAUNCH_OK … reason=window_count_increased_no_title_match` then immediately `Opening Cursor failed … elevated launch failed`.

**Status:** **STILL ACTIVE**.

### P0.5 Log sync silently not delivering — HIGH

**Three failure classes:**

| Detail | Meaning | Budgets (non-Force) |
|---|---|---|
| `mkdir_timeout_or_fail` | First SSH leg (`mkdir -p ~/.claude/logs`) failed | mkdir **3s** vs ConnectTimeout **8s** |
| `scp_or_append_fail` | mkdir OK; scp/cat/size-verify failed | scp 4s, cat 3s |
| `exception` / nullref | Generic catch | — |

**Nullref:** `File.WriteAllBytes` with null `$chunk` (Framework null-checks path not bytes). **Fixed** in workspace + Desktop `20260801.10\src` (guards ~611/813; typed breadcrumb `type=`/`at=`). **Not in git HEAD.** Still live in `20260801.9` / older. All 17 log hits use old bare format (no `type=`).

**Residual same class:** `$tmpLocal = Join-Path $env:TEMP …` (~610) lacks the helper's TEMP fallback (~452).

**Delivery gap (the real Aug 2 problem):**

- Callers use `Request-ConnectLogSync -NoInline`, which **returns before** stall/Force escape (≥60s + >8KB).
- Only ERROR → `Complete-ConnectLogAsyncDrain -Force`.
- Sole remaining path: `System.Timers.Timer` + `Register-ObjectEvent` — **WinPS 5.1 does not pump during `ReadKey`** (code comment admits this).
- **`LOG_SYNC_OK` does not exist** anywhere — success is silent; only proof is `.sync-offset`.
- Silent exits: no target (`return` ~519); all FAIL breadcrumbs gated on `$script:ConnectLogWriter` non-null.

| Day | Local bytes | Watermark | Undelivered |
|---|---|---|---|
| Aug 1 | 4,700,120 | 1,076,016 (froze ~22:47) | ~77% |
| Aug 2 | ~74,190 | **absent → 0** | **100%** |

Aug 1 also left `sync-pending = 1076016|524288|0` (chunk stuck mid-flight). Local zero-loss policy holds; **server forensics unreliable**.

**Where:** `connect-ui.ps1` ~452–487, ~534, ~610–874, ~884–989, ~1232–1269.

**Status:** Delivery **STILL ACTIVE / broken**; nullref fixed only uncommitted/Desktop.

---

## 6. P1 — Active or partially fixed

### P1.1 Bundle self-inconsistency → checksum_fail

**Event:** 12:25:00 local (`5ddd506d2836`) — `scp OK files=31` then `checksum_fail count=3 sample=mismatch:connect-env-repair.ps1` → `checksum_verify_failed`. Client aborted (correct). Full deploy ~12:56 healed share (`sha256sum -c` clean).

**Not CRLF:** deployer strips CR; e.g. repo `connect-env-repair.ps1` 21679 − 495 CR = **21184** = server. Client hashes scp'd bytes.

**Two structural causes (both live):**

1. **`deploy-client-bundle.sh` `server-fallback`** when `laptop-exec read` fails — stages from stale `/opt/...`. Abandoned `/var/tmp/claude-client-bundle-new.*` held **17719**-byte file vs share **21184**. Worse: fallback can *succeed* and ship week-old scripts with consistent checksums.
2. **Ad-hoc** `_ship-update-files.sh` / `_fix-bundle-checksums.sh` rebuild checksums from `manifest.txt` (narrower; one rewrites policy after hash) vs deployer `find` (broader) — interleaving breaks consistency. Manifest/policy byte sizes changed across the morning churn (581/29 → 556/28; policy 333 → 341).

**Status:** Specific breakage healed; **structure still live**.

### P1.2 Split-generation install (mutex / Trim / config lock)

| Crash | When | Root cause | Fixed in repo / Desktop `.10\src`? |
|---|---|---|---|
| `Get-SshConfigWriteMutex` not recognized | PREBOOT `PREBOOT_eb9c3778` 23:22 | IExpress→Desktop paired **new** `connect.ps1` (calls mutex) with **old** `git-mode.ps1` (no def). Not a dot-source order bug (`git-mode` sourced ~line 368, long before Set-SshHostBlock). | Yes — fail-open `Get-Command` + mutex in git-mode |
| `Object[].Trim` | `6a7fc1f3f6d5` 22:05 on `20260801.9` | SSH init exit 255 → no `MOUNT_HASH:` line → `-replace` on empty pipeline → empty `Object[]`. Caret at deferred `$boot = Initialize-ServerSession` is rethrow site. | Yes — `[string](... + '')` before `-replace`; pubkey `-Raw` |
| `.ssh\config` locked | 4–6× ~21:00 | Unlocked `Set-Content` under multi Connect | Yes — mutex + `Write-AsciiFileRetry` / `File.Replace` |

**Auth-verify (5× CONNECT_AUTH_NEEDED + verify fails):** same incident — five Connect instances on one slot within ~0.5s; `keyCopyOk=True` but alias verify failed while peers tore down Host block. Not a credential bug.

**Tests:**

- `test-ssh-config-multi-writer-hard.ps1` — mutex location, Local\\ before Global\\, File.Replace, 6-writer storm. **Gap:** does not simulate new-connect.ps1 + old-git-mode.ps1 pairing.
- `test-server-setup-round-trip-merge-live.ps1` — merge performance, not Trim-on-exit-255.
- `test-log-sync-nullsafe.ps1` — different path (`Sync-ConnectLogToServer`).

**Residual:** Version string `20260801.10` reused across broken/fixed trees → `connect.bat` freshness cannot self-heal. Fail-open mutex → silent loss of serialization. No bundle-cohesion check at dot-source. Flat root scripts were seen pre-fix during investigation; later only versioned `.10\src` remained.

### P1.3 Primary publisher slot-only (no liveness)

`Test-IsPrimaryTunnelPublisher`: slot ≠ 0 ⇒ `am_only=1` ⇒ `publish_port=0`. Server only reports divergence it was told to keep. No demotion when published port is dead. Most mismatch counts from hard tests are slot arithmetic — exclude from pain.

### P1.4 `state.vscdb` ~4.94 GB → auth sync permanently skipped

Threshold **500 MiB** (`cursor-auth-laptop.ps1` ~886–892). Live **4,943,134,720** bytes (~9.4× over; grew ~150MB / 4h on Aug 1). Mid-session AUTH never merges without `-Force`. Aug 2 looked OK only because stamp was "current".

`personal_cursor_dominant`: informational, console-suppressed; compounds warm-handoff crowding (`profile_all=9`).

### P1.5 Multi-Connect click-storm (~21:00 Aug 1)

Many `session start` on `20260801.5` within seconds → config races + auth verify fails. Same root as P1.2 file lock. Recommend startup concurrency guard (MULTI_INSTANCE assigned slots but did not prevent five processes claiming same slot).

---

## 7. P2 — Lower / already mitigated

| Item | Verdict |
|---|---|
| `PROXY_FALLBACK xray_closed` ×24 | Remote probe of server **10808** (not local sidecar). False-negative ConnectTimeout burns during Incident A. **ForceProbe shipped** (~16:15 Aug 1); 0 after; 0 on Aug 2. Keep fallback; fix was false trigger. |
| `CURSOR_PROXY_CLEAR backend_down` / `removed_18998_dead_proxy` | Intended recovery (front 18998 up, `-L` backend dead). Later `CLEAR_SKIP reason=windows_open` with many Cursor windows. |
| `WINDOWS_MCP probe_bad` ×3 | Raw: `http=000000 lport=18765` at 15:18:30, 17:10:18, 20:36:29 — curl `000` doubled (retry concat). **Not** 404/port 8000 (amirhossein, already migrated). During tunnel-down; Aug 2 clean on 18765. |
| `exe_promote` → System32 | Log: `SETUP: launch_dir=C:\WINDOWS\System32\WindowsPowerShell\v1.0` with archived `Claude-Connect-20260727.02.exe`. Sanitizer shipped; **residual:** `$WinDir` / `$ScriptDir` first candidates in `Get-ConnectExePromoteDirs` bypass gate. |
| `local_exe_drift` | Intended when version equal but EXE hash differs; all log hits `hardprom*` or publish window. |
| `LIVE_*_PROBE` | Test-only |
| `golden_stale` / `CURSOR_AUTH_INCOMPLETE` | Intermittent refresh timing |
| `MOUNT_BG_FAIL` key rejected | One-off ~17:06 Aug 1 |

---

## 8. Aug 2 marker table and session verdict

### 8.1 Whole-day tunnel markers

| Marker | Aug 1 | Aug 2 |
|---|---|---|
| `Unknown error` | 466 | **0** |
| `banner exchange` | 32 | **0** |
| `STALE_FORWARD` | 108 | **0** |
| `refuse_spawn` | 12 | **0** |
| `wait_timeout_budget_exhausted` | 18 | **0** |
| `TUNNEL_WAIT fail` | 24 | **0** |
| `TUNNEL_DROP` | 12 | **0** |
| `port_mismatch_keep` | 33+ | **0** |
| `ACTIVE_MOUNT mismatch` | 11 | **0** |
| `PROXY_FALLBACK xray_closed` | 24 | **0** |

**Why quiet (not a fix):** single instance slot 0; port free at spawn (`skip_release_stale`); tunnel up attempt=1; stable network; proxy healthy (`PROXY_HEALTH socks=18999 http=18998 ok=1`). Defects latent.

### 8.2 Session `bbcc62bf75e7` (~12:51+)

| Area | Result |
|---|---|
| Tunnel / mount / AGENT_PATH | OK (`primary_match=1`) |
| Cursor folder | OK after attempt 4 `folder-uri-classic` (12:53:06); `CURSOR_ON_FOLDER_OK` |
| Auth stamp | Skipped (stamp current); DB still oversized |
| Update 12:25 | Failed closed on inconsistent bundle (correct) |
| Log sync | **Not proven** — watermark 0; no `LOG_SYNC_OK` token exists |
| Storm defects | Latent — not exercised |

---

## 9. Live environment snapshot (~13:10–13:45 +0330)

| Check | Result |
|---|---|
| Smart conf | `TUNNEL_PORT=20020`, `ACTIVE_MOUNT=refactoreoldclub`, `GIT_MODE=off` |
| Smart tunnel / mount | Listening; sshfs up |
| CBM binary | GOOD size `270253064`; `--help` ok |
| Server xray | `active`; `127.0.0.1:10808` |
| Share | `20260801.10`; checksums consistent after morning heal |
| Server load | Spiked **~55 → ~20**; I/O wait; Amir `git status` **D-state** on sshfs (~5 min) |
| Smart Cursor profile DB | `state.vscdb` ≈ 4.94 GB |
| Connect processes | Single `connect-boot` on Desktop `20260801.10` (later check) |
| Desktop vs share sizes | Desktop `.10\src` matched share for key scripts; **repo working tree larger** (newer uncommitted) |

---

## 10. Causal map

```text
Laptop path blip (Wi-Fi/VPN/xray) — ms=66–130 Unknown error
  -> TUNNEL_EXIT
  -> amplifiers (no fail-cache, inverted backoff, foreign-banner fuser loop)
  -> zombie -R OR refuse_spawn self-deadlock (no rebind)
  -> user opens second Connect (slot1 / 20021)
  -> slot0 dead port stays published (no liveness)
  -> LOG_SYNC / WMCP / proxy probes fail as symptoms

Partial / split install (same version string, different files)
  -> Mutex missing / Trim crash / config lock / auth-verify race

Warm Cursor + weak LAUNCH_OK
  -> Confirm fails -> false "elevated launch failed"
  -> cold: wrong strategy order -> 40s + orphan PIDs

-NoInline + ReadKey (timer not pumped)
  -> watermark never advances (silent thin server logs)

deploy laptop-exec fail -> server-fallback
  OR ad-hoc ship helpers (manifest vs find checksums)
  -> inconsistent or silently-old fleet bundle
```

---

## 11. Corrections vs earlier fleet narrative

| Fleet claim | Smart-specific truth |
|---|---|
| Unknown error ≈ MaxStartups / multi-user SSH storms | **One Smart session** after local path blip + client amplifiers |
| Dual Connect caused the stall | Dual Connect was **response** to refuse_spawn (~6 min later) |
| WMCP 404/8000 on Smart | Smart had `http=000000` on **18765** during tunnel-down |
| No LOG_SYNC_FAIL on Aug 2 ⇒ sync OK | Watermark **0** — delivery silent-failed |
| Aug 2 quiet ⇒ tunnel bugs fixed | **Latent**; code paths unchanged since 2026-07-29 |

---

## 12. Ranked fix order (recommendations only — not done)

1. **Break refuse_spawn self-poison** — ignore current-pass marker, or implement rebind; add streak cap (`git-mode.ps1`). Highest-value: only unrecoverable stall needing manual second window.
2. **Classify SSH error banners** — never treat `Unknown error` / timeout text as foreign peer; skip clear when unreachable.
3. **Restore backoff after streak ≥6**; negative banner cache; classify `Unknown error` in `SshX` for circuit breaking.
4. **Unify launch success** — Confirm must accept Launch's evidence (or Launch must not return true on window-count alone); fix "elevated" error text; one warm fallback; reap losing-strategy PIDs; re-benchmark order for Cursor 3.13.10 (`folder-uri-classic` earlier).
5. **Log sync:** stall/Force check **before** `-NoInline` return; pump drain from menu/`ReadKey`; emit `LOG_SYNC_OK`; raise non-Force mkdir budget (≥ ConnectTimeout + margin); TEMP fallback at chunk path; commit `connect-ui.ps1` hardenings; breadcrumb when writer null.
6. **Deploy:** hard-fail (or refuse promote) on `server-fallback`; stamp `BUNDLE_SOURCE_KIND`; post-swap `sha256sum -c`; unify ad-hoc ship helpers to `find` rule or delete them; log full `$bad` list not only `$bad[0]`; **bump version on every content change**.
7. **Primary publisher liveness** — demote/publish when published port dead and another slot is up.
8. **Profile DB** — vacuum/rebuild `ClaudeServerCursorProfile-Smart` (4.94 GB); do not only raise threshold.
9. **Gate `$WinDir`/`$ScriptDir`** in exe promote dirs; retire archived System32-CWD SFX EXEs.
10. **Bundle cohesion** — assert `connect.ps1` + `git-mode.ps1` same build at dot-source; extend multi-writer test to mismatched pairing; Connect startup concurrency guard.
11. **Ops:** one Connect slot; investigate Amir git-on-sshfs D-state for fleet load; optional `TEST_` prefix on LIVE probes; WMCP `http=000` double-print cosmetic.

---

## 13. Appendix — evidence pointers

| Topic | Key log / code |
|---|---|
| Storm A/B | `23f2a722cf0d` 14:58–15:04 and 16:57–17:10 in `connect-20260801.log` |
| Dual Connect workaround | `3469e31724f7` from 17:04 |
| Stress LOG_SYNC | `f91322b6e9cd` / `vstress` ~22:47 |
| Checksum fail | `5ddd506d2836` 12:25:00 Aug 2 |
| Launch OK Aug 2 | `bbcc62bf75e7` 12:53:06 `LAUNCH_OK folder-uri-classic` |
| PREBOOT mutex crash | `PREBOOT_eb9c3778` 23:22 Aug 1 |
| Trim crash | `6a7fc1f3f6d5` 22:05 Aug 1 on `20260801.9` |
| System32 promote | `0f866dda6cd7` / `d1b2229e086f` ~21:22 Aug 1 + `launch_dir=…\WindowsPowerShell\v1.0` |
| WMCP Smart | three `http=000000 lport=18765` lines (see §7) |
| refuse_spawn intro | git `405b4c1`; plan `2026-07-29-zombie-owner-reseed-tunnel-ready.md` |
| ForceProbe | `git-mode.ps1` Ensure-Tunnel ~3534+; shipped ~16:15 Aug 1 |

### Completeness checklist (all agent domains merged)

- [x] Tunnel: timeline A/B, amplifiers table, refuse_spawn deadlock proof, foreign-banner, dual-Connect causality, PUSH_CONF/am_only, Aug 2 zero table, latent-not-fixed note
- [x] Log sync: three FAIL classes, nullref fix status, TEMP residual, hour-22 stress, NoInline starvation, watermark table, no LOG_SYNC_OK, sync-pending, writer-null silence, deploy drift
- [x] Launch/auth: predicate mismatch, warm single-strategy, orphan PIDs, strategy order wrong, auth=config race, db_too_large, personal_cursor_dominant, version multi-content
- [x] Update/proxy/WMCP: CRLF ruled out, server-fallback + ad-hoc checksum rules, System32 CWD + residual gate hole, hardprom drift, ForceProbe, WMCP 000/18765, LIVE probes
- [x] Mutex/Trim: split-generation proof, Trim empty pipeline, unlocked Set-Content, test gaps, residual version collision / fail-open
- [x] Live load / Amir D-state / CBM / xray / share health
- [x] Fleet narrative corrections + ranked fixes

*End of report.*
