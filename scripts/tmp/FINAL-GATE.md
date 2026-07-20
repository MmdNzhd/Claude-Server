# FINAL-GATE

**OVERALL: FAIL**

- Generated: 2026-07-20T11:52:00+03:30 (approx; after Start-Sleep/wait + gate run)
- Root: D:\Smart\Claude-Code-Server
- Failed: 1 / 6
- Agent: independent verify; laptop-exec -p claude-code-server only; no deploy
- Runner: `scripts/tmp/final-gate.ps1` (hard-fail; exit 1)

| Check | Result | Evidence |
|-------|--------|----------|
| 1.connect.ps1 no curly quotes U+201C/U+201D/U+2018/U+2019 | **PASS** | matches=0 file=scripts/client/windows/connect.ps1 |
| 2.git-mode.sh seq 1 12 twice in wait fns; zero seq 1 4 | **PASS** | seq_1_12=2 seq_1_4=0 (lines ~889 and ~907: `for i in $(seq 1 12)`) |
| 3.recover_mounts single sshx remote `timeout 30 $CM recover-one` NOT `timeout 30 sshx "$CM` | **PASS** | good_sshx_timeout30_recover-one=1; bad_timeout30_sshx_CM=False; recover-one_sshx_count=1; L1006: `sshx "timeout 30 $CM recover-one ..."` |
| 4.git-mode.ps1 banner_miss_tcp_open_budget AND ensure action=reseed | **PASS** | banner_miss_tcp_open_budget=True; action=reseed=True |
| 5.test-connect-pipeline.ps1 exit 0 | **PASS** | exit=0; All tests passed |
| 6.test-git-mode-deep.ps1 exit 0 | **FAIL** | exit=1; **1 test(s) failed:** `FAIL  editor-launch.sh does not match any folder-uri` |

## Verdict

OVERALL **FAIL** - gate exit 1.

Hard-fail cause: check 6 only. Static source checks 1-4 and test-connect-pipeline passed.
