# Fleet problem inventory — 2026-08-01

Evidence from live probes on `smart@192.168.210.240` (sshd journal, connect / laptop-exec logs, binary hashes, reverse-tunnel laptop pulls). Status as of ~2026-08-01 15:30 server / ~19:00 local.

**Scope:** Smart site developers (amir, aria, amirhossein + fleet). Not Sepidz.

**Legend**

| Priority | Meaning |
|---|---|
| P0 | Active pain / load / broken I/O — fix first |
| P1 | Causes disconnects, wrong paths, or multi-user waste |
| P2 | Latency / UX / hygiene — fix after P0–P1 |
| P3 | Process / tooling gaps (this investigation session) |

---

## P0 — Fix first

### P0.1 Corrupt `codebase-memory-mcp` binary (17 users) — crash loop

| Field | Detail |
|---|---|
| What | Per-user `~/.local/bin/codebase-memory-mcp` (~258MB) is truncated/corrupt vs good copy |
| Proof | GOOD size `270253064` (smart / pardis / rezaashrafi / administrator). BAD size `270249937`. `good.replace(b'\r\n', b'\n') == bad` (CRLF→LF ate legitimate `0x0D0A` bytes). BAD exits **132** / `Illegal instruction` / dmesg `trap invalid opcode` |
| Wave | BAD mtime cluster **2026-07-27 08:54**; smart repaired **09:17** |
| Impact | Cursor MCP respawns → continuous crash loop → CPU/load; MCP shows Connection closed; Aria RAM complaints; Amirhossein still BAD (live exit 132 @ 15:28) |
| Who BAD | Most users including **aria, amir, amirhossein**, parsa, hamed.kh, mehrdad, … (17 BAD / 4 GOOD) |
| Fix | Copy good binary from `/home/smart/.local/bin/codebase-memory-mcp` → all BAD homes; chmod +x; optional: disable `codebase-memory-mcp` in `mcp.json` until stable; prevent future CRLF “text mode” copy/sync of this binary |

### P0.2 Aria: `smartshared` SSHFS NOT_MOUNTED → hour-scale agent latency

| Field | Detail |
|---|---|
| What | ACTIVE_MOUNT=`smartshared` but dir empty / not in `/proc/mounts`; leftover `.leftover-smartshared-*`; no healthy sshfs for aria project |
| Impact | Agents fall through to **laptop-exec over tunnel**: live `le status` ~**33s**, `le run` ~**53s**; log reads/writes **30–223s**; `CMD_TIMEOUT`×3, `MUX_RECREATE`×12, `TUNNEL_DOWN`×1 |
| Symptom | Local Cursor answers ~5 min; Remote SSH session felt ~**1 hour** (dozens of file ops × 30–160s) |
| Fix | Remount `smartshared`, restart `claude-watchdog`, one Connect slot only, reload Cursor window |

### P0.3 SSH one-shot storms (amir worst; fleet-wide pressure)

| Field | Detail |
|---|---|
| What | Many short SSH sessions to server:22 (p50 duration ~**0.4s** for amir) |
| Evidence | amir today ~**3008** Accepted from WAN `195.114.9.180`; dual Connect overnight (~every 60–65s each → ~15s combined on sshd); amirhossein ~**1798** Accepted |
| Drivers | Dual/triple Connect windows; health probes; log sync retries; old Connect clients |
| Impact | sshd / MaxStartups pressure; `Unknown error` on connect to :22; flapping tunnels |
| Fix | One Connect per user; update client; prefer LAN; reduce probe cadence if still storming |

### P0.4 Multi-slot reverse tunnels (same user, multiple `-R` ports)

| User | Ports seen | Notes |
|---|---|---|
| **amir** | 20060 + 20061 (+ used 20062) | STALE_FORWARD fights; `ENSURE_TUNNEL wait_timeout`×34 |
| **aria** | 20040 + 20041 | soft_fail / TUNNEL_DROP |
| **amirhossein** | **20050 + 20051 + 20054** | conf=`20051` but sshfs `smartmsgine` on **20054**, `menu_items_labeler` on **20050** |
| **hamed.kh** | 20110 + 20111 | dual |
| **smart** | 20020 + 20021 | dual |

| Impact | Port wars, wrong tunnel for LE vs mount, recovery loops, editor reopen skips |
| Fix | Kill extra Connect instances; leave one slot; align conf TUNNEL_PORT with mount sshfs `-p` |

### P0.5 Smart Playwright Chrome runaway (~99% CPU)

| Field | Detail |
|---|---|
| What | `ms-playwright-mcp` / Chrome renderer under smart cache stuck high CPU (>1h observed) |
| Impact | Fleet load average elevated (saw ~8–23, later ~5–11) → everyone feels slow |
| Fix | Kill runaway Chromium/node for smart playwright MCP; restart MCP only if needed |

---

## P1 — Disconnects, wrong path, multi-user waste

### P1.1 Fleet `ssh: Unknown error` to `192.168.210.240:22`

| Field | Detail |
|---|---|
| What | Client logs: `ssh: connect to host 192.168.210.240 port 22: Unknown error` |
| Who (high counts) | mehrdad / parsa / hamed.kh worst; also amir, amirhossein (153×), aria |
| Related | Hard `ClientAliveInterval 15` / `CountMax 3` (~45s); `MaxStartups 30:30:200`; TIME-WAIT high; storms from P0.3 |
| Fix | After killing storms + load: re-measure; consider softer ClientAlive; confirm MaxStartups headroom |

### P1.2 Amir: WAN + stale Connect + port wars

| Field | Detail |
|---|---|
| IP | `195.114.9.180` (WAN, not office LAN) |
| Connect | **`20260727.11`** (far behind ~`20260801.5`) |
| Ports | Dual/triple 20060–62; overnight two session ids |
| Profiles | `profile_count=9` |
| Fix | One Connect; update client; prefer LAN when in office |

### P1.3 Amirhossein: mount OK but multi-tunnel + BAD CBM + stale Connect

| Field | Detail |
|---|---|
| Mount/LE | Healthy: mount read ~110–530ms; LE status/run ~0.9–1.5s — **not** Aria-class |
| Pain | BAD CBM crash loop; **3 tunnels**; Connect **`20260729.14`**; windows-mcp 404; heavy MCP RSS |
| Fix | Same as P0.1 + collapse to one Connect + update client + fix windows-mcp |

### P1.4 Aria / Amir: connect day-log sync broken

| Field | Detail |
|---|---|
| What | `LOG_SYNC_FAIL mkdir_timeout_or_fail`; server day log thin (often only `[multiagent]` from audit); `sync-pending=0|524288|0` |
| Impact | Ops blind on server; laptop has truth (`~/.config/claude-connect/logs/`) |
| Pulled copies | `/home/amir/tmp-laptop-logs/connect-20260801.log`; `/home/aria/tmp-logs/connect-20260801.log` |
| Fix | After tunnel/mount stable: force log sync; fix mkdir path/timeout on laptop side if still failing |

### P1.5 Proxy / xray flaky (client fallbacks)

| Field | Detail |
|---|---|
| What | `PROXY_FALLBACK mode=server_direct reason=xray_closed`; backend down markers |
| Who | aria, amirhossein, others |
| Impact | Auth/proxy path churn; slower editor/agent traffic |
| Fix | Stabilize xray/sidecar; ensure Connect proxy health checks match current ports (18998/18999) |

### P1.6 windows-mcp probe failures

| Field | Detail |
|---|---|
| What | `WINDOWS_MCP: server_sync_probe_bad http=404 lport=8000` (amirhossein ×24+×19 sessions) |
| Impact | Prefer-path WRITE/Glob via MCP fails → mount/LE failover; agents slower |
| Fix | Repair windows-mcp on laptop (ensure script / port / auth); one healthy listener |

### P1.7 Stale / inconsistent Connect client versions

| User | Version seen |
|---|---|
| amir | `20260727.11` |
| amirhossein | `20260729.14` |
| aria | Desktop claimed `20260801.5` but running log also showed older `20260725.37` in places |
| Target | **`20260801.5`** (match `connect-version.txt` / connect.ps1) |

| Fix | `deploy-client-bundle` + user update (`u` / auto-update) or re-publish; kill old Connect processes |

### P1.8 Duplicate / oversized MCP packs per user

| Field | Detail |
|---|---|
| What | Cursor pack + ECC duplicates: many `npx` / `mcp-remote` / playwright / chrome-devtools / memory |
| Evidence | aria ~21 MCP-related procs; amirhossein ~13+ with hundreds of MB RSS each |
| Impact | RAM + CPU on server; slow extensionHost |
| Fix | Trim duplicate ECC MCP entries; keep single pack via `sync-cursor-mcp`; disable unused servers |

---

## P2 — Latency / hygiene

### P2.1 Hard sshd ClientAlive (15s × 3 ≈ 45s)

Aggressive keepalive closes quiet reverse tunnels under load / NAT / WAN. Revisit after storms fixed.

### P2.2 High TIME-WAIT / concurrent users

~50 users logged; elevated TIME-WAIT; correlates with short SSH churn.

### P2.3 Many Cursor profiles / open windows

amir `profile_count=9`; recovery paths skip auth relaunch when profile windows open — can leave stale auth/tunnel state.

### P2.4 `GIT_MODE=off` / push-conf failures

amirhossein: `GITMODE: PUSH_CONF fail exit=255`; GIT_MODE=off. Not the main slowness, but conf drift.

### P2.5 mehrdad empty ACTIVE_MOUNT (seen earlier)

Conf / mount inconsistency for some users — agents get wrong project / no mount.

### P2.6 Dual sshfs mounts per user without single ACTIVE_MOUNT discipline

amirhossein: `smartmsgine` + `menu_items_labeler` both mounted on **different** tunnel ports — ACTIVE_MOUNT only points at one.

### P2.7 Install / sync path that can CRLF-corrupt binaries

Root cause of P0.1 wave — any future `add-user` / copy / dos2unix / text-mode transfer of `codebase-memory-mcp` will re-break fleet. Guard in install/sync docs + scripts.

### P2.8 Aria leftover mount dirs

`.leftover-smartshared-*` clutter; clean after successful remount.

---

## P3 — Investigation / tooling gaps

### P3.1 `user-memory` MCP unavailable in this Cursor session

Cannot persist findings to Memory MCP (`GetMcpTools` / server missing). User may need Reload Window after `sudo claude-server sync-cursor-mcp`.

### P3.2 Server-side connect logs incomplete for some users

Because of P1.4 — do not trust thin server `connect-YYYYMMDD.log` alone; pull laptop day log via reverse tunnel.

---

## Per-user snapshot (2026-08-01)

| User | Mount | LE latency | Tunnels | CBM | Connect ver | Top pain |
|---|---|---|---|---|---|---|
| **aria** | **NOT_MOUNTED** smartshared | **30–50s+** | 20040+20041 | BAD crash | mixed / old lines | Dead mount → hour-scale agents |
| **amir** | (varies; dual Connect) | storm-driven | 20060+20061 | BAD | `20260727.11` | WAN + SSH storm + dual slot |
| **amirhossein** | OK smartmsgine | ~1s | **20050+51+54** | BAD crash | `20260729.14` | CBM loop + 3 tunnels + MCP load |
| **fleet others** | mixed | mixed | some dual | mostly BAD | mixed | Unknown error + CBM + load |
| **smart** | OK (sample) | OK | dual 20020/21 | GOOD | — | Playwright CPU runaway |

---

## Recommended fix order

1. **P0.1** Copy good `codebase-memory-mcp` to all BAD users (or disable MCP entry fleet-wide).
2. **P0.5** Kill smart Playwright/Chrome runaway.
3. **P0.2** Remount Aria `smartshared` + one tunnel + watchdog.
4. **P0.4 / P0.3** Collapse dual/triple Connect (amir, aria, amirhossein, hamed.kh, …).
5. **P1.7** Push Connect update to amir / amirhossein / anyone on old versions.
6. **P1.6** Fix windows-mcp on affected laptops.
7. **P1.4** Verify log sync after tunnels stable.
8. **P1.5 / P1.1 / P2.1** Proxy + sshd ClientAlive / Unknown-error re-measure.
9. **P1.8 / P2.7** Trim duplicate MCPs; harden binary install against CRLF.

---

## Evidence paths

| Artifact | Path |
|---|---|
| Server connect logs | `/home/<user>/.claude/logs/connect-YYYYMMDD.log` |
| laptop-exec logs | `/home/<user>/.claude/logs/laptop-exec-YYYYMMDD.log` |
| Amir laptop log copy | `/home/amir/tmp-laptop-logs/connect-20260801.log` |
| Aria laptop log copy | `/home/aria/tmp-logs/connect-20260801.log` |
| CBM binary | `/home/<user>/.local/bin/codebase-memory-mcp` |
| Good reference binary | `/home/smart/.local/bin/codebase-memory-mcp` |
| Connect conf | `/home/<user>/.claude-connect.conf` |
| Probe notes | `/tmp/aria-perf.sh`, `/tmp/ah-perf.sh` on server |

---

## Solutions applied (2026-08-01 ~16:15 UTC)

Plan: [`docs/superpowers/plans/2026-08-01-fleet-pain-remediation.md`](../superpowers/plans/2026-08-01-fleet-pain-remediation.md)

| Item | Result |
|---|---|
| P0.1 CBM ×17 | Copied good `270253064` to all BAD; `--help` ec=0 / 0.9.0; fleet **21 GOOD / 0 BAD** |
| P0.5 Playwright | Killed smart `ms-playwright-mcp` Chrome tree; load **~24 → ~3.3** |
| P0.2 Aria mount | `smartshared` MOUNTED; LE ~2.5s; leftovers removed |
| P0.4 Multi-slot | Collapsed amir/amirhossein/hamed/smart extras to conf ports; amirhossein dual-sshfs downed |
| P0.2b Parsa | Tunnel **DOWN** — needs user Connect; `claude-mount up projects` blocked |
| P1.7 Connect | Desktop files pushed **`20260801.6`** (SOCKS ForceProbe + path clear); **must relaunch** Connect for running process |
| P1.5 / P0.6 VPN | Server xray active/200; Aria probe cache cleared; SOCKS `-ForceProbe` retry shipped in `git-mode.ps1` |
| P1.6 WMCP | amirhossein migrated **18765** (was 8000) |
| P1.8 MCP | `sync-cursor-mcp` aria / amirhossein / hamed.kh |
| P2.5 mehrdad | Tunnel down + empty ACTIVE_MOUNT — user must pick project (no blind `LAPTOP_USER` edit) |
| P2.7 ELF guards | `add-user.sh` post-install gate; `claude-self-heal` ELF skip; `verify.sh` fleet size check — installed live |
| Client share | `/usr/local/share/claude-client` **v20260801.6** ship-gates passed |

### Complete ship (2026-08-01 ~16:45 UTC) — v20260801.7

| Item | Status |
|---|---|
| CBM ×21 | GOOD / 0 BAD |
| Playwright | gone |
| Load | ~1.2 |
| Aria/amir/amirhossein mounts + LE | OK (~1–1.8s) |
| Single-slot amir/aria/amirhossein/smart | OK |
| WMCP amirhossein | **18765 stable** (legacy-8000 sticky fixed in client) |
| Server share | **`20260801.7`** ship-gates passed |
| Desktop push | aria / amir / amirhossein / smart → `20260801.7` + WMCP killer |
| ELF guards | live on server |
| SOCKS ForceProbe | in share git-mode.ps1 |
| parsa / hamed.kh / mehrdad tunnels | DOWN until those users open Connect |

**Users must relaunch Connect once** so the *running* process picks up `20260801.7` (Desktop files already updated).

### Verification re-check (2026-08-01 ~16:30 UTC)

| Gate | Status |
|---|---|
| CBM fleet | **PASS** — 0 BAD, sample `--help` ec=0 |
| Playwright | **PASS** — gone |
| Load | **PASS** — ~3.5–4.6 (was ~24) |
| Share `20260801.6` + SOCKS ForceProbe + PathsForClear | **PASS** |
| ELF guards live (`self-heal` / `add-user` / `verify`) | **PASS** |
| amirhossein mount + LE | **PASS** — MOUNTED, LE ~1s, single port 20051 |
| amir single slot | **PASS** — 20060 only |
| Aria mount / LE | **FAIL → cleared stuck tunnel** — port 20040 was listening but **banner exchange timed out** (half-dead `-R`); killed sshd pid; Aria must start **one** Connect to remount |
| smart dual slot | Recurs (20021 respawns) — kill extras; smart should keep **one** Connect |
| parsa / hamed / mehrdad tunnels | **DOWN** — user Connect required |
| HealBlackhole sidecar tests | **Known debt** — intentionally stripped in `186ad0a`; server ship-gate does **not** require it (PathsForClear gate passes) |

### Still needs user action

1. **aria**: quit Connect under `Downloads\Claude-Connect\20260729.14\` → start **one** from `Desktop\Claude-Connect\` (`20260801.7`) so reverse tunnel gets SOCKS/HTTP `-L` (ForceProbe).
2. **amirhossein**: same — quit `Downloads\...\20260729.14` Connect (tunnel **20051 DOWN** as of ~16:55Z after stale WMCP-forward surgery) → start **one** Desktop `20260801.7`.
3. **amir**: Desktop Connect OK for WMCP; optional relaunch if still on pre-`.7` boot path.
4. **parsa / hamed.kh / mehrdad**: Connect when back (mehrdad: pick project; no blind `LAPTOP_USER` edit).
5. **smart**: keep a **single** Connect (avoid second slot `20021` / old `20260729.17` tree).
6. **Cursor**: Reload Window after CBM fix (if not done).
7. **ClientAlive**: deferred until after relaunch + quiet load.

### Deep probe (2026-08-01 ~16:50–16:55 UTC) — root of “Desktop=`.7` but still broken”

| Finding | Proof |
|---|---|
| **Desktop push ≠ running process** | Aria / amirhossein `connect-boot.ps1` still under `Downloads\Claude-Connect\20260729.14\src\` while Desktop `connect-version.txt` = `20260801.7` |
| **Aria VPN empty `-L`** | Live laptop ssh: `-R 20040:localhost:22` only — **no** SOCKS/HTTP local forwards; server xray socks `10808` HTTP 200; laptop has no 18998/19080 listen |
| **amirhossein WMCP sticky** | Maintain every ~3m logged `WMCP_LPORT=8000`; server forward was `-L 127.0.0.1:28005:127.0.0.1:8000` until killed |
| **Server env alone insufficient** | Rewrote `~/.config/windows-mcp/env` → `LOCAL_PORT=18765`; live ssh `-L` still targeted **8000** until process restart |
| **Forward retarget flap** | Killing AH `-L 28005` coincided with **20051 Connection refused**; short sshd Accepted/closed from `192.168.40.191` continue (~1/min) but **no `-R` listener** → needs user Connect relaunch |
| **CBM / load** | Still 0 BAD traps after 15:51; load ~3–4; aria/amir tunnels up |

**Product debt:** heal/push that only updates `Desktop\Claude-Connect` leaves portable `Downloads\Claude-Connect\{oldver}\` runners in memory. Next harden: detect ScriptDir under Downloads older than Desktop (or share) and force handoff / warn.

*End of inventory.*
