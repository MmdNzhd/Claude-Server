# STAGE-0 Evidence Pack

## ID
- Stage: 0 (baseline)
- CONNECT_VERSION (repo): `20260722.40` (`scripts/client/windows/connect.ps1`, `scripts/client/mac/connect.sh`)
- Live client last seen: `20260722.38` (session `6c8884b5220c` @ 18:27)
- Timestamp (UTC): 2026-07-22T16:55:00Z approx (plan execute start)
- deploy_ran=no

## VERIFY
- Live log file: `/home/smart/.claude/logs/connect-20260722.log`
- Session fingerprint (latest healthy Smart): `session=6c8884b5220c` `ENV version=20260722.38` `VERDICT_CODE=CURSOR_ON_FOLDER_OK` ~18:27
- Smoking-gun still present earlier same day:
  - `session=6c8884b5220c` `ACQUIRE_FAST no_probe_ports` → `ORPHAN_TUNNEL: kill … port=20027 reason=unprotected_live` → `ACQUIRE_FAST claim_sticky port=20027` (18:25)
  - `session=48959888542e` `syntax error near unexpected token $'do\r'` on `for p in 20026 20027; do` (16:22)
  - `session=b3ef3f44f713` `UPDATE_FORCE` + `applied_ok` (18:25)
  - `session=84a0d47796e2` `LOG_SYNC_REBUILD local=309234 remote_was=622761` shrink (17:22)
- Code anchors (pre-fix):
  - `scripts/client/git-mode.ps1` `Acquire-TunnelPort` still uses `$port` / sticky reclaim / orphan kill
  - `Get-SessionTunnelPort` / `candPort` absent at Stage 0 start
- Ops already applied (user YES, not Stage D):
  - `/usr/local/share/claude-client` → `claude-client.disabled-20260722-164945` + `claude-client.FROZEN`
  - Legacy profile archived; Desktop Sepidz launchers neutralized
- still_live=yes for Stages 1/1b/2/3/6b signals listed in LIVE_GATE

## RESEARCH
N/A — Stage 0 baseline only (no production patch).

## RED_TEST
N/A — Stage 0 baseline only.

## IMPLEMENT
- Files touched: none (baseline capture + this pack)
- Intent: freeze must-disappear signatures and version baseline before Stage 1
- drive_by=none

## GREEN_TEST
N/A — Stage 0 baseline only.

## LIVE_GATE
Must-disappear (or become absent after later stages) signatures:
1. `ACQUIRE_FAST no_probe_ports` followed by sibling `ORPHAN_TUNNEL: kill … unprotected_live`
2. `bash: syntax error near unexpected token $'do\r'`
3. `ACQUIRE_SKIP: foreign_peer cached port=20028` permanent own-block pin without TTL
4. PushConf / exit log port shadow (`TUNNEL_EXIT … port=20029` while claim sticky 20027)
5. `UPDATE_FORCE` / Quiet `applied_ok` under optional policy (Stage 6b)
6. `LOG_SYNC_REBUILD` when `local < remote_was` (Stage 9)
7. Mid-session `CURSOR_PROXY_CLEAR` with open windows (Stage 6d; currently gone post-15:00)

## GATE
`STAGE_0_DONE` 2026-07-22T16:55Z `deploy_ran=no` N+1 unlocked (Stage 1)
