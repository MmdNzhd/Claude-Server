# LOCK STATUS 2026-07-20

## GREEN (verified after re-apply + parse fix + editor-launch assert)
- Mac seq 1 12 (not 4)
- Mac recover single sshx (no nested)
- Win banner_miss_tcp_open_budget DROP
- Win Ensure action=reseed (no TUNNEL_REUSED on banner miss)
- git-mode.ps1 parses cleanly
- connect.ps1 no curly quotes
- test-connect-pipeline: All tests passed
- test-git-mode-deep: All deep git-mode tests passed

## NOTE
Parallel agents repeatedly overwrote P0 fixes; parent re-applied and re-verified.
Do not deploy until user approval. P1 sweep agents may still be running — watch for regressions on git-mode.sh/ps1.
