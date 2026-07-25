# Worked Plan Shapes

## Example A — .NET API bug (null ref in checkout)

**Guns:** `NullReferenceException at OrderService.Checkout`  
**Spine:** Baseline → Reproduce RED → Root-cause lock → Fix GREEN → Artifact sync → Runtime gate → Closeout → Release LOCKED  
**Authoritative:** `dotnet test --filter Checkout_DraftSku`  
**Pack shape:** see `assets/EXAMPLE-PACK-FILLED.md`  
**Closeout shape:** see `assets/EXAMPLE-CLOSEOUT-FILLED.md`  
**Failure mode avoided:** GREEN tests while IIS still serves old DLL

## Example B — React + API contract drift

**Guns:** UI toast `INVALID_COUPON` though API returns 200  
**Stages:**
0. Baseline guns + identities  
1. Network fixture / HAR capture (investigate)  
2. API contract RED (`pytest` or Pact)  
3. UI adapter fix + vitest RED→GREEN  
4. Playwright journey adjacent verify  
5. Sync `dist/` SHA to static host staging  
6. Closeout  
D. Release LOCKED  

**Do not:** fix UI only without API contract RED.

## Example C — Python worker poison message

**Guns:** `ack timeout queue=invoices` spike  
**Stages:** Reproduce with fixture → hypothesis ledger → pytest RED on parser → fix → container image digest = staging tag → metric gate window  
**Artifact:** image digest match (not just `latest`)

## Example D — Infra client false DONE (Connect-class)

**Guns:** force-update log line; orphan tunnel kill  
**Observed failure:** repo GREEN, Desktop half-synced, live session old version  
**Closeout must report:** `ARTIFACT_SYNC=DRIFT` + `LIVE_GATE=pending_reconnect` even if `SUITE_OK`  
**Recovery:** R3 full sync_set + R4 relaunch + gun rescan ([recovery](recovery.md))  
**Product DONE:** only after scorecard AND — never from stage progress lines

## Example E — Intermittent race

**Guns:** `TOCTOU stale mount` ~30% of sessions  
**Path:** [intermittent-repro](intermittent-repro.md) → stabilize → probabilistic RED → fix → RUNTIME_GATE metric over window (not one log line)  
**Class:** A if user path; C if harness-only flake

## Example F — Release unlock

User: `deploy کن` (new message)  
→ Stage D pack: VERIFY quotes unlock; `deploy_ran=yes`; post-release RUNTIME_GATE  
Non-unlock: `تمام` / `done` / `execute the plan` → stay LOCKED
