# Fleet Pain Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop justified fleet complaints on Smart (`192.168.210.240`) by fixing corrupt `codebase-memory-mcp`, killing Playwright CPU runaway, remounting dead projects, collapsing multi-slot tunnels, restoring Connect xray `-L` VPN path, and hardening so CRLF cannot re-corrupt CBM.

**Architecture:** Wave A is server ops only (immediate load relief). Wave B is laptop Connect/VPN/WMCP/log-sync/MCP trim (needs user or reverse-tunnel actions). Wave C is small repo guards + inventory doc. Wave D is deferred remeasure (ClientAlive / non-blockers) only after A+B quiet. Do not change sshd ClientAlive in Wave A. Do not dismiss user gripes until post-Wave-A gate passes (`load < 5`, CBM GOOD, Playwright gone, LE &lt; 3s for aria/amirhossein).

**Tech Stack:** Smart Linux server (`sudo-from-laptop --smart`), SSH reverse tunnels (`20000+(UID-1000)*10+slot`), `claude-mount` / `laptop-exec`, Connect client `20260801.5` (`scripts/client/`), xray on `127.0.0.1:10808/10809`, Cursor MCP pack.

**Evidence / cursor plan:** [`docs/connect-fix-evidence/FLEET-PROBLEMS-20260801.md`](../../connect-fix-evidence/FLEET-PROBLEMS-20260801.md) · Cursor plan `fleet_problem_fixes_a61469c8`.

## Global Constraints

- English only in repo files (no Persian).
- Never print secrets (Figma bearer, WMCP auth, OAuth).
- CBM good reference: `/home/smart/.local/bin/codebase-memory-mcp` size `270253064`.
- CBM BAD size: `270249937` (17 users) — never `sed`/`dos2unix` this ELF.
- Connect target version: `20260801.5` (server share already deployed under `/usr/local/share/claude-client`).
- WMCP preferred local port: `18765` (avoid `8000`).
- Xray success: spawn log `socks_port=19080 http_port=19180` + `proxy_leg=-L` + `PROXY_HEALTH ok=1`.
- Mount remount = `claude-mount up <id>` (not `recover` alone).
- Do not blind-edit mehrdad `LAPTOP_USER=Smart`.
- Do not tune `claude-mount-reaper` in Wave A.
- SOCKS ForceProbe code change only if Wave B still shows empty `socks_port=` after quiet load + `20260801.5`.

## File map (Wave C code only)

| File | Responsibility |
|---|---|
| `scripts/server/commands/add-user.sh` | Post-install CBM ELF/size/`--help` gate after step 4b |
| `scripts/server/claude-self-heal.sh` | Hard-skip ELF / `codebase-memory-mcp` before any `sed 's/\r$//'` |
| `scripts/server/commands/deploy-laptop-exec.sh` | Same ELF-skip on strip helper if present |
| `scripts/server/commands/verify.sh` | Fleet CBM size check |
| `scripts/client/git-mode.ps1` | Optional Wave B.5: SOCKS ForceProbe retry (mirror HTTP) |
| `docs/connect-fix-evidence/FLEET-PROBLEMS-20260801.md` | Full matrix + Solutions applied |

Wave A/B primarily mutate server homedirs / processes / laptop Connect — not git until Wave C.

---

## Wave A — Immediate server relief (do first)

### Task 1: Copy good CBM to all BAD users

**Files:**
- Ops only: `/home/<user>/.local/bin/codebase-memory-mcp`
- Reference: `/home/smart/.local/bin/codebase-memory-mcp`

**Interfaces:**
- Consumes: good binary size `270253064`, sha of smart
- Produces: every former BAD home size/sha matches smart; `--help` exit 0

- [ ] **Step 1: Baseline count BAD vs GOOD**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
GOOD=270253064
for f in /home/*/.local/bin/codebase-memory-mcp; do
  u=$(echo $f|cut -d/ -f3); sz=$(stat -c%s "$f")
  [ "$sz" = "$GOOD" ] && t=GOOD || t=BAD
  echo "$t $u $sz"
done | sort
'
```

Expected: 17 BAD, 4 GOOD (`smart`, `pardis`, `rezaashrafi`, `administrator`).

- [ ] **Step 2: Install good binary into every BAD home**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
set -e
SRC=/home/smart/.local/bin/codebase-memory-mcp
GOOD=270253064
for home in /home/*; do
  u=$(basename "$home")
  dst="$home/.local/bin/codebase-memory-mcp"
  [ -f "$dst" ] || continue
  sz=$(stat -c%s "$dst")
  [ "$sz" = "$GOOD" ] && continue
  install -m 755 -o "$u" -g "$u" "$SRC" "$dst"
  echo "FIXED $u"
done
'
```

Expected: lines `FIXED <user>` for each BAD user.

- [ ] **Step 3: Verify each user `--help` ≠ 132**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
for u in amir amirhossein aria danial designer fateme hamed hamed.kh kiana mahdie mehrdad mohammad parsa pouyan reza tarane testuser2; do
  sudo -u "$u" timeout 5 /home/$u/.local/bin/codebase-memory-mcp --help >/tmp/cbm-$u.out 2>&1
  echo "$u ec=$?"
done
'
```

Expected: each `ec=0` (or timeout 124 if help waits — must NOT be 132). Output should mention `0.9.0`.

- [ ] **Step 4: Confirm dmesg new traps slowing**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
dmesg -T | grep codebase-memory | tail -5
sleep 30
dmesg -T | grep codebase-memory | tail -3
'
```

Expected: no new trap lines after ~1–2 minutes once users Reload (may still see a few until Reload).

- [ ] **Step 5: Ask active Cursor users to Reload Window** (aria, amir, amirhossein, hamed.kh, parsa, mehrdad) — ops chat, not code.

---

### Task 2: Kill smart Playwright Chrome runaway

**Files:**
- Ops: processes under `smart` with `ms-playwright-mcp` / `mcp-chrome-*`

- [ ] **Step 1: Identify PIDs**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
ps -eo pid,pcpu,etime,user,cmd --sort=-pcpu | grep -E "ms-playwright|mcp-chrome|playwright-mcp" | grep -v grep | head -20
'
```

Expected: Chrome renderer ~100% CPU, user `smart`, `user-data-dir=.../ms-playwright-mcp/...`.

- [ ] **Step 2: Kill the tree**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
# kill chrome under ms-playwright-mcp user-data-dir, then parent node/npm if still up
pkill -u smart -f "ms-playwright-mcp/mcp-chrome" || true
pkill -u smart -f "playwright/mcp" || true
sleep 2
ps -eo pid,pcpu,user,cmd | grep -E "ms-playwright|mcp-chrome" | grep -v grep || echo "playwright_gone"
'
```

Expected: `playwright_gone` or no ~100% renderer.

- [ ] **Step 3: Load check**

```bash
sudo-from-laptop --smart -p claude-code-server -- uptime
```

Expected: load trending down within 1–3 minutes (not necessarily <5 yet until CBM stops).

---

### Task 3: Remount Parsa `projects` (NOT_MOUNTED)

**Files:**
- Ops: `/home/parsa/.claude-connect.conf`, `/home/parsa/mounts/projects`

- [ ] **Step 1: Confirm tunnel for parsa block**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
ss -tln | grep -E ":2008[0-9]"
cat /home/parsa/.claude-connect.conf
'
```

Expected: at least one of `20080–20089` listening; `ACTIVE_MOUNT=projects`.

- [ ] **Step 2: Mount up (not recover-only)**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
sudo -u parsa -H env HOME=/home/parsa bash -lc "
  claude-mount up projects
  laptop-exec status -p projects
  ls /home/parsa/mounts/projects | head
"
'
```

Expected: `sshfs: MOUNTED`, entries > 0, `tunnel: UP`.

- [ ] **Step 3: If tunnel DOWN**

Tell Parsa: one Connect only, then re-run Step 2. Do not proceed to claim mount fixed without `MOUNTED`.

---

### Task 4: Collapse multi-slot reverse tunnels

**Files:**
- Ops + user action on laptops

**Live offenders (re-check before acting):**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
ss -tln | awk "{print \$4}" | grep -E ":20[0-9]{3}$" | sed "s/.*://" | sort -n | uniq
'
```

| User | Block | Keep one |
|---|---|---|
| amir | 20060–69 | conf port |
| amirhossein | 20050–59 | conf port |
| hamed.kh | 20110–19 | conf port |
| smart | 20020–29 | conf port |

- [ ] **Step 1: Message users to quit extra Connect windows** (keep one).

- [ ] **Step 2: Re-check single listen port per block**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
for spec in "amir:2006" "amirhossein:2005" "hamed.kh:2011" "smart:2002" "aria:2004"; do
  u=${spec%%:*}; p=${spec##*:}
  echo -n "$u: "; ss -tln | grep -E ":${p}[0-9]" | wc -l
done
'
```

Expected: ideally `1` listen line set per user (count of ports = 1).

- [ ] **Step 3: After collapse, remount ACTIVE if needed**

```bash
# example amirhossein — align mount to remaining port
sudo -u amirhossein -H env HOME=/home/amirhossein claude-mount up smartmsgine
```

- [ ] **Step 4: Amirhossein dual-sshfs hygiene (P2.6)**

If both `smartmsgine` and `menu_items_labeler` mounted on different `-p` ports:

```bash
sudo -u amirhossein -H env HOME=/home/amirhossein bash -lc '
  # keep ACTIVE only
  claude-mount down menu_items_labeler || true
  claude-mount up smartmsgine
  findmnt /home/amirhossein/mounts | head
'
```

- [ ] **Step 5: Tell Amir** — one Connect; prefer office LAN over WAN `195.114.9.180` when possible (P1.2).

---

### Task 5: Aria keep-up + LE timing gate + leftovers

- [ ] **Step 1: Status**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
sudo -u aria -H env HOME=/home/aria bash -lc "
  start=\$(date +%s%N)
  laptop-exec status -p smartshared
  end=\$(date +%s%N)
  echo le_ms=\$(( (end-start)/1000000 ))
  grep smartshared /proc/mounts || echo NOT_MOUNTED
"
'
```

Expected after Wave A: `MOUNTED`, `le_ms < 3000` (stretch: <2000).

- [ ] **Step 2: If NOT_MOUNTED**

```bash
sudo -u aria -H env HOME=/home/aria claude-mount up smartshared
```

- [ ] **Step 2b: Clean leftover mount dirs (P2.8)**

```bash
sudo -u aria -H bash -lc 'ls -d /home/aria/mounts/.leftover-smartshared-* 2>/dev/null; rm -rf /home/aria/mounts/.leftover-smartshared-*'
```

Only after `findmnt` shows healthy `smartshared`.

- [ ] **Step 2c: Aria Cursor windows** — ask Aria to close extra server-profile windows until `profile_count` is low (was 9; blocks proxy clear).

- [ ] **Step 3: Wave A gate (fleet)**

```bash
sudo-from-laptop --smart -p claude-code-server -- bash -lc '
uptime
dmesg -T | grep codebase-memory | tail -2
ps -eo pcpu,cmd | grep ms-playwright | grep -v grep || echo playwright_gone
# CBM sample
stat -c%s /home/aria/.local/bin/codebase-memory-mcp
stat -c%s /home/parsa/.local/bin/codebase-memory-mcp
'
```

**Wave A PASS criteria (then you may start pushing back on vague “still slow”):**
- load 1m **< 5** (or clearly falling under 8)
- aria/parsa/amir/amirhossein CBM size `270253064`
- `playwright_gone`
- parsa `projects` MOUNTED
- aria + amirhossein `laptop-exec status` **< 3000 ms**
- no multi-port for amir/aria/amirhossein/hamed (best effort if users offline)

- [ ] **Step 4: Spot-check amirhossein LE** (P1.3 baseline)

```bash
sudo -u amirhossein -H env HOME=/home/amirhossein bash -lc '
  start=$(date +%s%N); laptop-exec status -p smartmsgine >/dev/null; end=$(date +%s%N)
  echo le_ms=$(( (end-start)/1000000 ))
'
```

Expected: `le_ms < 3000`.

---

## Wave B — Laptop Connect / VPN / WMCP

### Task 6: Force running Connect `20260801.5`

**Files:**
- Laptop: `Desktop\Claude-Connect\` / auto-update from `/usr/local/share/claude-client`
- Server share already has `connect-version.txt` = `20260801.5`

- [ ] **Step 1: Confirm server bundle**

```bash
cat /usr/local/share/claude-client/windows/connect-version.txt
# Expected: 20260801.5
```

- [ ] **Step 2: Per user — quit ALL Connect, run update/`u`, start ONE Connect**

Priority order: **aria** (`20260725.37`) → hamed.kh (`20260725.41`) → amir (`20260727.11`) → mehrdad/parsa/amirhossein.

- [ ] **Step 3: Verify from laptop day log (via tunnel)**

```bash
# example aria — adjust port
ssh -i /home/aria/.ssh/claude_laptop -p 20040 -o BatchMode=yes User@127.0.0.1 \
  "powershell -NoP -C \"Select-String -Path \$env:USERPROFILE\\.config\\claude-connect\\logs\\connect-*.log -Pattern CONNECT_VERSION= | Select-Object -Last 1\""
```

Expected: `CONNECT_VERSION=20260801.5`.

---

### Task 7: Restore xray `-L` VPN path (ops)

**Files:**
- Laptop: `%USERPROFILE%\.config\claude-connect\xray-probe-cache.json`
- Code ref: `scripts/client/git-mode.ps1` Ensure-SessionTunnel (~3479)

- [ ] **Step 1: After Task 6, clear probe cache if stuck CLOSED**

On laptop (PowerShell):

```powershell
Remove-Item -Force -ErrorAction SilentlyContinue "$env:USERPROFILE\.config\claude-connect\xray-probe-cache.json"
```

- [ ] **Step 2: Re-ensure tunnel (Reconnect / new Connect)**

- [ ] **Step 3: Success criteria in connect log**

Must see:
- `ENSURE_TUNNEL proxy_leg=-L local=19080 remote=10808`
- `ENSURE_TUNNEL spawned ... socks_port=19080 http_port=19180`
- `PROXY_HEALTH ... ok=1`
- NOT empty `socks_port=` + `PROXY_FALLBACK ... server_direct` as steady state

- [ ] **Step 4: Server xray sanity (should already be true)**

```bash
systemctl is-active xray
sudo -u aria curl -sS -m 3 --socks5-hostname 127.0.0.1:10808 https://www.google.com -o /dev/null -w "%{http_code}\n"
```

Expected: `active`, `200`.

---

### Task 8: WMCP migrate `8000` → `18765`

**Files:**
- `scripts/client/windows/windows-mcp-laptop.ps1` (behavior reference)
- Laptop listener + server `windows-mcp-forward`

- [ ] **Step 1: On affected laptop (parsa / amirhossein first)**

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8000,18765 -ErrorAction SilentlyContinue |
  Select-Object LocalPort, OwningProcess
```

- [ ] **Step 2: Kill wrong process on 8000; ensure MCP on 18765 via Connect ensure**

- [ ] **Step 3: Local probe**

```powershell
# Expect HTTP 200 on /mcp with auth from env — use Connect ensure path; do not log secrets
```

- [ ] **Step 4: Reconnect once; server log must show `server_sync_probe_ok` or non-404**

---

### Task 9: Mehrdad ACTIVE_MOUNT + Hamed mount

- [ ] **Step 1: Mehrdad** — user selects project in Connect (do **not** rewrite `LAPTOP_USER=Smart` without confirmation). Then:

```bash
sudo -u mehrdad -H env HOME=/home/mehrdad claude-mount up <PROJECT_ID>
grep ACTIVE_MOUNT /home/mehrdad/.claude-connect.conf
```

- [ ] **Step 2: Hamed.kh** — one of 20110–112; `claude-mount up main`; update Connect off `20260725.41`.

---

### Task 9b: Log sync + Parsa TEMP hygiene (P1.4 + live TEMP_CLEANUP)

- [ ] **Step 1: After tunnels stable**, force Connect log sync (session end or ERROR path / `Complete-ConnectLogAsyncDrain -Force` equivalent by restarting Connect once).

- [ ] **Step 2: Verify amir/aria server day logs grow** beyond thin `[multiagent]`-only content:

```bash
wc -c /home/amir/.claude/logs/connect-$(date +%Y%m%d).log /home/aria/.claude/logs/connect-$(date +%Y%m%d).log
```

Expected: sizes rising after sync (not stuck ~11KB for amir).

- [ ] **Step 3: Parsa TEMP_CLEANUP** — on Parsa laptop, delete stuck `%TEMP%\claude-connect-chunk-*.log` if `TEMP_CLEANUP_FAIL` continues after Connect update (low priority; not load driver).

---

### Task 9c: Trim duplicate MCP packs (P1.8)

Priority users with heavy npx stacks: aria, amirhossein, hamed.kh.

- [ ] **Step 1:** Inspect `~/.cursor/mcp.json` for duplicate ECC vs pack servers.

- [ ] **Step 2:**

```bash
sudo claude-server sync-cursor-mcp aria
sudo claude-server sync-cursor-mcp amirhossein
sudo claude-server sync-cursor-mcp hamed.kh
```

- [ ] **Step 3:** User Reload Window. Confirm fewer duplicate `npx`/`mcp-remote` procs:

```bash
ps -u aria -o cmd= | grep -cE 'npx|mcp-remote|playwright-mcp' || true
```

---

### Task 10 (optional Wave B.5): SOCKS ForceProbe retry

**Only if** after Wave A+B quiet load + `20260801.5`, spawn still shows empty `socks_port=` while server xray curl 200.

**Files:**
- Modify: `scripts/client/git-mode.ps1` (Ensure-SessionTunnel SOCKS probe, ~3479)
- Mirror pattern in `Add-TunnelHttpProxyLeg` (`ForceProbe` / `open_on_retry`)
- Test: `scripts/client/tests/test-xray-http-leg-resilience.ps1` (extend or sibling for SOCKS)

- [ ] **Step 1: Write failing test** asserting SOCKS path retries ForceProbe once on timeout before `skipping_proxy_leg`.

- [ ] **Step 2: Implement minimal retry** — on first inconclusive/timeout, call `Test-RemoteXraySocksOpen -ForceProbe` once; only then clear ports / skip `-L`.

- [ ] **Step 3: Run client tests**

```bat
scripts\client\tests\run-all.bat
```

Or targeted xray tests under `scripts/client/tests/test-xray-*.ps1`.

- [ ] **Step 4: Bump connect-version + deploy-client-bundle**

```bash
sudo claude-server deploy-client-bundle
```

- [ ] **Step 5: Commit** (only if user asked to commit)

```bash
git add scripts/client/git-mode.ps1 scripts/client/tests/test-xray-*.ps1 scripts/client/windows/connect-version.txt scripts/client/mac/connect-version.txt
git commit -m "$(cat <<'EOF'
fix(connect): retry SOCKS xray probe before skipping -L legs

Timeouts were treated like closed xray and dropped VPN legs for the whole tunnel spawn.
EOF
)"
```

---

## Wave C — Prevention + docs

### Task 11: CBM ELF guards

**Files:**
- Modify: `scripts/server/commands/add-user.sh` (after step 4b ~272)
- Modify: `scripts/server/claude-self-heal.sh` (`_heal_bin_crlf_all`)
- Modify: `scripts/server/commands/verify.sh`

- [ ] **Step 1: add-user post-install gate** — after curl\|bash, require size≈good or `head -c4` ELF magic `\x7fELF` and `timeout 5 --help` exit≠132; else warn and `cp` from `/home/smart/...` if present.

- [ ] **Step 2: self-heal** — before any `sed 's/\r$//'`, skip if file is ELF or basename is `codebase-memory-mcp` or `xray`.

- [ ] **Step 3: verify.sh** — loop homes, warn if CBM size ≠ `270253064` when file exists.

- [ ] **Step 4: Deploy**

```bash
sudo claude-server install
# or targeted deploy scripts as used in this repo
```

- [ ] **Step 5: Commit** (if user requested)

```bash
git add scripts/server/commands/add-user.sh scripts/server/claude-self-heal.sh scripts/server/commands/verify.sh
git commit -m "$(cat <<'EOF'
fix(server): guard codebase-memory-mcp against CRLF/text corruption

Fleet BAD binaries matched CRLF stripping of ELF; skip sed on binaries and verify sizes.
EOF
)"
```

---

### Task 12: Inventory doc rewrite

**Files:**
- Modify: `docs/connect-fix-evidence/FLEET-PROBLEMS-20260801.md`

- [ ] **Step 1: Merge** hairline matrix, live gate @15:47Z, Solutions applied timestamps, BAD/GOOD lists, per-user socks matrix, Parsa NOT_MOUNTED.

- [ ] **Step 2: Link** this plan: `docs/superpowers/plans/2026-08-01-fleet-pain-remediation.md`.

---

## Wave D — Deferred (only after Wave A+B quiet)

### Task 13: Remeasure Unknown / ClientAlive (P1.1 / P2.1)

- [ ] **Step 1:** Count `Unknown error` in last 2h of connect logs for mehrdad/parsa/hamed/amir after Wave A+B.

- [ ] **Step 2:** If still high with single Connect + load&lt;5 + `20260801.5`, then consider sshd `ClientAliveInterval 30` / `ClientAliveCountMax 4` (single controlled change + `sshd -t` + reload). **Not before.**

### Task 14: Deferred non-blockers (document only unless recurring)

| Item | Action if still noisy |
|---|---|
| P1.13 `laptop-exec rpath` DIE | Fix agent prompts / skill text — not infra |
| P2.4 GIT_MODE / PUSH_CONF | One healthy tunnel then reconnect |
| P2.2 TIME-WAIT | Follows from storm death |
| P3.1 user-memory MCP missing | `sudo claude-server sync-cursor-mcp smart` + Reload Window |
| P1.14 reaper knobs | Re-check zombie rate; tune only if pass3 still hurts after Wave A |
| Idle BAD users without connect today | Still fixed by Task 1 CBM copy |

---

## Complete coverage matrix (inventory → task)

| Inventory ID | Covered by |
|---|---|
| P0.1 CBM corrupt ×17 | Task 1 + Task 11 |
| P0.2 Aria mount / hour LE | Task 5 (+ Task 1/2) |
| P0.3 SSH storms | Task 4 + Task 6 + Wave A gate |
| P0.4 Multi-slot | Task 4 |
| P0.5 Playwright | Task 2 |
| P1.1 Unknown error | Wave A side-effect + Task 13 |
| P1.2 Amir WAN + old Connect | Task 4 Step 5 + Task 6 |
| P1.3 Amirhossein slow | Task 1 + Task 4 + Task 5 Step 4 + Task 8 |
| P1.4 Log sync fail | Task 9b |
| P1.5 Proxy / xray flaky | Task 7 (+ Task 10 if needed) |
| P1.6 WMCP 404 / 8000 | Task 8 |
| P1.7 Stale Connect versions | Task 6 |
| P1.8 Duplicate MCP | Task 9c |
| P2.1 ClientAlive | Task 13 (remeasure only after A+B) |
| P2.2 TIME-WAIT | Task 14 (follows storm death) |
| P2.3 Many Cursor profiles | Task 5 Step 2c |
| P2.4 GIT_MODE / PUSH_CONF | Task 14 |
| P2.5 mehrdad empty ACTIVE_MOUNT | Task 9 |
| P2.6 Dual sshfs without ACTIVE | Task 4 Step 4 |
| P2.7 CRLF binary path | Task 11 |
| P2.8 Aria leftovers | Task 5 Step 2b |
| P3.1 user-memory missing | Task 14 |
| P3.2 Incomplete server connect logs | Task 9b |

**Live findings added after inventory (must not be dropped):**

| Live finding | Covered by |
|---|---|
| Parsa `projects` NOT_MOUNTED @15:47Z | Task 3 |
| Empty SOCKS `-L` / Aria VPN “socket closes” | Task 7 (+ Task 10) |
| Hamed.kh MOUNT_FAILED ×12 + Connect `20260725.41` | Task 6 + Task 9 |
| Parsa TEMP_CLEANUP_FAIL | Task 9b |
| `laptop-exec rpath` DIE | Task 14 |
| mount-reaper orphan kills | Task 14 (observe; no Wave A tune) |
| Server share already `20260801.5` | Task 6 (verify only; laptop must update) |

Placeholder scan: no TBD. `<PROJECT_ID>` for mehrdad is intentionally user-chosen at runtime.

---

## Self-review (writing-plans checklist)

| Spec item | Task |
|---|---|
| CBM 17 BAD repair | Task 1 |
| Playwright CPU | Task 2 |
| Parsa NOT_MOUNTED | Task 3 |
| Multi-slot collapse | Task 4 |
| Aria LE / mount / leftovers / profiles | Task 5 |
| Connect 20260801.5 | Task 6 |
| VPN empty `-L` | Task 7 (+ optional 10) |
| WMCP 8000→18765 | Task 8 |
| mehrdad / hamed | Task 9 |
| Log sync + TEMP | Task 9b |
| Duplicate MCP | Task 9c |
| ELF guards | Task 11 |
| Inventory | Task 12 |
| ClientAlive remeasure | Task 13 |
| Non-blockers listed | Task 14 |
| No ClientAlive in W1 | Global Constraints |
| Upgrade≠VPN alone | Task 7 wording |
| recover≠remount | Task 3/5 use `up` |

**Completeness verdict:** Every P0/P1 inventory item maps to a task; P2/P3 either have a step or explicit Wave D deferral. Ready for execution choice.

---

## Execution handoff

Plan saved to [`docs/superpowers/plans/2026-08-01-fleet-pain-remediation.md`](2026-08-01-fleet-pain-remediation.md).

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks (`superpowers:subagent-driven-development`)
2. **Inline Execution** — this session with checkpoints (`superpowers:executing-plans`)

**Which approach?**

**Urgent note:** Live load was ~24 with Playwright + CBM crash loop — start **Wave A Tasks 1–2** immediately when you approve execution; do not wait on Wave B laptop updates to kill CPU pain.
