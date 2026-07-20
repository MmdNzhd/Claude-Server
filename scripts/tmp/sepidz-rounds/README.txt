Sepidz 50-round log loop — agent instructions

On AGENT_LOOP_TICK_sepidz50:
1. Run: bash /tmp/sepidz-log-rounds/run-one-round.sh
2. If NEW fixable problems found and fixed in code/server:
   - ALWAYS publish Sepidz: 
     laptop-exec run -p claude-code-server -- powershell -NoProfile -ExecutionPolicy Bypass -File publish/publish.ps1 -SepidzOnly
   - NEVER publish/deploy Smart (Smart frozen, currently 20260717.22)
   - Record new version in that round's report section
3. Residual-only (FARZAD_TUNNEL_DOWN / STALE_TUNNEL needs laptop reconnect): no publish needed unless code changed
4. Mirror report: already done by run-one-round.sh
5. Do NOT start a second loop
6. Stop when ALL_50_COMPLETE

POLICY: every code/server fix => Sepidz publish. Smart version stays fixed.
