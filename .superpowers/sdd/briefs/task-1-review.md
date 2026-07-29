# Task 1 Review (re-review after scope fix): ReseedEffective / CanBindL

**Reviewer:** read-only (spec + quality)  
**Range:** `c5fc940` .. `186ad0a` (CanBindL `6a178c2` + strip `186ad0a`)  
**Artifacts:** `task-1-brief.md`, `task-1-report.md`, `reviews/task-1-diff.txt`

---

## SPEC: PASS

| Requirement | Verdict | Evidence |
|---|---|---|
| D1 Gap Ensure never kills for proxy reseed | **Met** | Behavioral: real `Ensure-SessionTunnel` → `kill_count=0`, `$true`, `TunnelReused=$true`, log `foreign_owner_cannot_bind` |
| D2 bg_init never keeps `needReseed` under Gap | **Met** | `connect.ps1` clears `needReseed` + `bg_init_reseed_skip reason=foreign_owner_cannot_bind`; static + D2 sim |
| S1 MUST NOT kill solely for ReseedRaw when NOT CanBindL | **Met** | Win 4 Ensure fallthroughs → `Test-ProxyReseedShouldKill`; Mac `proxy_reseed_should_kill` + pre-kill belt |
| S2 `foreign_owner_cannot_bind` Win+Mac+connect.ps1 | **Met** | Present in Ensure log, bg_init, Mac ensure (+ belt) |
| S1 MUST NOT put Claim/CanClaim inside ReseedRaw | **Met** | `Test-TunnelNeedsProxyReseed` Claim-free |
| Ensure gate before `killing stale bg` | **Met** | Chokepoint before kill string; Gap early-return |
| S4 kill_count=0 Gap + positive kill_count>=1 | **Met** | Both call product Ensure; suite PASS 26 asserts (re-run this review) |
| Preferred chokepoint | **Met** | `Test-ProxyReseedShouldKill` / `proxy_reseed_should_kill` |
| Claim `stale_non_connect` adopt | **Met** | Win+Mac Claim tightened |

---

## QUALITY: Approved

Prior Critical/Important from first review are cleared by `186ad0a`:

| Prior finding | Status |
|---|---|
| CRITICAL HealBlackhole sneak-in in `connect.ps1` | **Cleared** — no `HealBlackhole` / `Invoke-CursorProxySidecarHealBlackhole` in Task 1 `connect.ps1` range; `c5fc940..HEAD` connect.ps1 is **+8 lines bg_init gate only** |
| IMPORTANT ConnectVersion/BuildId bump | **Cleared** — restored `20260729.2` / `b332a4c2-…` (matches base) |
| IMPORTANT UTF-8 BOM | **Cleared** — first bytes `35,32,99` (`# R…`); BOM=NO |

CanBindL scope retained: foreign_owner gate + `Test-CanClaimCursorProxyOwner` needReseed clear still present.

### Critical

None.

### Important

None.

### Minor (non-blocking)

1. **D2 behavioral is inline sim**, not executing `connect.ps1` product code — allowed by brief (“source+sim”); static gate assert compensates.
2. **Win lacks Mac-style pre-kill belt** — Gap covered by four chokepoint early-returns; belt is defense-in-depth only.

---

## Verdict

**SPEC PASS · QUALITY Approved**

Task 1 DoD met; prior sneak-ins removed; `connect.ps1` delta vs base is bg_init CanBindL gate only. No Critical/Important remaining.
