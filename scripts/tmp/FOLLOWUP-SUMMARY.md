# Follow-up after agent flood (2026-07-20)

## Still GREEN (re-checked)
- Mac seq 1 12 / recover single sshx
- Win banner_miss budget + ensure reseed + no_proc DROP
- curly quotes scrubbed
- Log flush contracts PASS (Agent M)
- Mount contracts PASS (Agent P)
- Auth TEMP + merge PASS
- Lock verify PASS

## Just fixed now
- #24 foreign-session: ss failure → SS:UNKNOWN, do NOT auto-clear conf (Win+Mac)

## Stale reviews (superseded — ignore as current truth)
- Early REVIEW-TUNNEL / SCOREBOARD claimed P0 still open; later FIX-AGENT-3/4 + LOCK-VERIFY contradict
- Tunnel-hard "no_proc no DROP" — tree now has no_proc_tcp_open_budget

## Still open / caution (no deploy)
- connect-design leftovers may still vary by file; designer useVk PASS in spot check
- update-server.sh OAuth path / live server perms need deploy-time ops (user said no deploy)
- askpass echo: spot check PASS now
- Parallel agents may still race — re-gate before user deploy approval
