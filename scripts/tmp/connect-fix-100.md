# Connect Fix Checklist (100) — SepidzOnly, never Smart deploy

Rules for agents: laptop-exec -p claude-code-server only; repo-relative paths; no commit unless asked; bump version once at end.

## Wave A — P0 detect/actuate (1–20)
1. [x] INV: map all Clear-SessionMount call sites (Win+Mac)
2. [x] FIX: auto-recovery must NOT Clear-SessionMount when editor on folder
3. [x] VER: unit/string assert + log path simulation
4. [x] INV: map Stop-SessionTunnelCleanup call sites
5. [x] FIX: auto-recovery prefer reattach/ENSURE without killing live -R if Cursor needs it
6. [x] VER: assert recovery path skips TUNNEL_STOP when editor open (configurable)
7. [x] INV: Sync-SessionTunnelProcess ¬P branch asymmetry
8. [x] FIX: on ¬P path: CIM reattach + TCP soft_fail before tunnel_down
9. [x] FIX: debounce N consecutive fails (e.g. 3) before auto recovery
10. [x] VER: test soft_fail when tcp open + empty banner
11. [x] INV: finally block always kills tunnel
12. [x] FIX: finally keep -R alive if editor still on remote folder (opt-in flag default on)
13. [x] VER: disconnect Q still cleans; window-close policy documented
14. [x] INV: Remove-LocalOrphanTunnel / Acquire-TunnelPort kill live tunnels
15. [x] FIX: do not kill ssh -R that matches current session Port+pid
16. [x] FIX: ENSURE must not kill healthy reused tunnel
17. [x] VER: ORPHAN_KILL regression test
18. [x] INV: ExitOnForwardFailure interaction with flap
19. [x] FIX: consider ServerAlive tuning / log exit reason of -R process
20. [x] VER: log WaitForExit exit code on tunnel death

## Wave B — P1 stability (21–40)
21. [x] INV: double ENSURE after recovery (52724 then 9724)
22. [x] FIX: single ENSURE per recovery generation
23. [ ] VER: RecoveryGeneration gate
24. [ ] INV: port slot churn 21003→21002 mid-session
25. [ ] FIX: sticky TUNNEL_SLOT once session started unless hard conflict
26. [ ] VER: slot sticky test
27. [ ] INV: STALE_FORWARD port still busy
28. [ ] FIX: safer clear (no broad pkill) + longer/smarter wait
29. [ ] VER: busy-port path
30. [ ] INV: fuser -k collateral damage
31. [ ] FIX: narrow kill to sshd forward listeners only
32. [ ] VER: no pkill -f wide patterns
33. [x] INV: cursor relaunch false negative after recovery
34. [x] FIX: trust on_folder after KnownOnFolder; avoid forced relaunch
35. [ ] VER: editor-launch test
36. [ ] INV: ForceCursorAuthSync every recovery
37. [ ] FIX: throttle auth --force (e.g. once/5min unless tokens missing)
38. [ ] VER: AUTH_DECISION skip path
39. [ ] INV: elevated=yes side effects on process visibility
40. [ ] FIX/DOC: document elevated requirements; avoid dual integrity tunnels

## Wave C — P2 perf/noise (41–60)
41. [x] INV: self-heal on every PUSH_CONF
42. [x] FIX: remove self-heal from Push-ServerConnectConf hot path
43. [x] FIX: throttle self-heal (startup once / hourly / explicit)
44. [x] VER: PUSH_CONF no longer invokes heal; time budget
45. [ ] INV: PUSH_CONF call frequency
46. [x] FIX: strengthen dedupe window / skip identical
47. [ ] VER: push count in short session
48. [x] INV: PERF[cim_query] flood
49. [x] FIX: gate PERF logs behind ConnectPerf flag (default off)
50. [x] VER: day log size without PERF flood
51. [x] INV: TUNNEL_SYNC TRACE every tick
52. [x] FIX: enforce 30s TRACE throttle in shipped bundle
53. [x] VER: TRACE interval >= 30s
54. [ ] INV: Sync-ConnectLogToServer duplicate append
55. [ ] FIX: server append idempotent / watermark / no full re-sync
56. [ ] VER: DUP_FRAC near 0 on re-sync
57. [ ] INV: idle loop 236ms
58. [x] FIX: sleep 500–1000ms when healthy
59. [ ] VER: tick interval
60. [ ] INV: banner probe cost (~500ms x3)

## Wave D — P2/P3 quoting & packages (61–75)
61. [x] FIX: banner probe debounce + TCP before declaring down
62. [x] VER: no tunnel_down on single empty banner
63. [ ] INV: SshX bash -lc quoting for complex remotes
64. [ ] FIX: base64-wrap remote scripts for PUSH_CONF / foreign probe if still needed
65. [ ] VER: no syntax error near elif
66. [ ] INV: Warn-Foreign probe
67. [ ] FIX: safe foreign probe quoting
68. [ ] VER: foreign session test
69. [ ] INV: wrong package claude-code-client boot
70. [ ] FIX: refuse/warn if script_dir contains claude-code-client on Sepidz target
71. [ ] VER: boot guard message
72. [ ] INV: version skew fleet
73. [x] FIX: bump CONNECT_VERSION; SepidzOnly publish path ready
74. [x] VER: connect-version.txt Win+Mac match
75. [ ] INV: Mac parity gaps for P0 fixes

## Wave E — Mac parity + docs (76–88)
76. [x] FIX: git-mode.sh Sync/recovery parity for soft_fail/debounce
77. [x] FIX: connect.sh finally/orphan policy parity
78. [x] VER: test-mac / test-git-mode-deep asserts
79. [x] FIX: docs/client-connect.md recovery policy section
80. [x] FIX: docs: tunnel lifetime vs Cursor
81. [ ] VER: doc links match code
82. [ ] INV: OpenSSH_for_Windows-only banner
83. [x] FIX: accept Mac OpenSSH banners when LAPTOP_OS=mac
84. [ ] VER: banner OS matrix test
85. [ ] INV: Connection refused noise classification
86. [ ] FIX: log level/noise for expected pre-ENSURE refused
87. [ ] VER: cleaner WARN set
88. [ ] DOC: Smart 210.240 cannot reach 250.70 (ops note)

## Wave F — observability + verify gate (89–100)
89. [x] FIX: log ssh -R exit code on death
90. [x] FIX: structured RECOVERY reason enum
91. [ ] FIX: reduce False/True string noise in DEBUG (optional)
92. [ ] FIX: ensure session end line always written
93. [x] VER: tests/test-git-mode-deep.ps1 updated
94. [x] VER: tests/test-connect-pipeline.ps1 updated
95. [x] VER: run Win-relevant Pester/string tests via laptop-exec
96. [x] VER: Mac shell tests that exist
97. [ ] PUBLISH-PREP: SepidzOnly only (never Smart)
98. [ ] E2E-PREP: checklist for live Sepidz user smoke
99. [x] MULTI-AGENT review: code-reviewer on combined diff
100. [ ] FINAL: status board — all P0 VER green before publish ask

