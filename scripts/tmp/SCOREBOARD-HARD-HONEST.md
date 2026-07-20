# HARD testing — honest postmortem (2026-07-20)

## What user asked
Hard multi-agent tests so shipped bugs do not reach them.

## What HARD10 actually did
- Mostly source-grep contracts + mid-race agent reports marked STALE
- Parent scoreboard said CODE READY while single-instance mutex, call-before-define, weak FAIL logging, and flat swap remained

## Bugs that hit the user (proof HARD10 was insufficient)
1. Single-instance block
2. Ensure-ConnectRunId CommandNotFound
3. Failures not greppable as FAIL in day log
4. UPDATE swap_fail subdirectory on flat/temp layouts

## Gate now
- `test-hard-multi-agent-regressions.ps1` (wired in run-all.ps1)
- Parallel gap reports under scripts/tmp/HARD-GAP-*.md
- Do not claim HARD PASS / CODE READY without this suite green
