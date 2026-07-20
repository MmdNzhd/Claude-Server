# FIX-W1 - laptop-exec softfail / curly quotes / EditorSeenOpen

Agent: W1 | Project: claude-code-server | No deploy | No commit

## Fix A - curly/smart quotes in scripts/client/windows/connect.ps1

Status: PASS (already clean on laptop; verified).

- Replaced / confirmed absent: U+201C U+201D U+2018 U+2019 and U+2014.
- KeyChar / Persian comment already uses ASCII `-`.
- Verify: Get-Content -Raw must -notmatch '[\u201C\u201D\u2018\u2019]' -> PASS
- Pipeline parse assert for windows\connect.ps1 -> PASS

## Fix B - Win softfail / banner_miss (bugs 25, 77, 78, 84)

File: scripts/client/git-mode.ps1
Functions: Sync-SessionTunnelProcess, Ensure-SessionTunnel

1. banner_miss_tcp_open: INCREMENT TunnelSoftFailCount (do not reset to 0). At >=6 log TUNNEL_DROP (banner_miss_tcp_open_budget) and return $false. Under budget return $true (do not fall through).
2. no_proc_tcp_open: at SoftFailCount >=6 log TUNNEL_DROP (no_proc_tcp_open_budget) and return $false (hard DROP). Under budget with no proc return $true; if reattached continue into bg-alive probe.
3. bg-alive tick: do not reset TunnelSoftFailCount on every alive tick - only a healthy banner probe may reset.
4. Ensure-SessionTunnel on banner_miss: must NOT return success / TUNNEL_REUSED. Log action=reseed and fall through to kill stale bg + reseed.

Also cleaned a mojibake comment in Get-TunnelBanner ("Positive cache only - never cache...").

## Fix C - EditorSeenOpen sticky (bugs 79, 80)

File: scripts/client/windows/connect.ps1
Status: PASS (present on laptop; verified).

- Clears EditorSeenOpen when editor window is not open (EDITOR_SEEN_CLEAR on session_open / session_poll / auto_recovery / finally).
- Does not force $editorOpened=$true from sticky alone ("never force editorOpened from sticky alone").
- No remaining: elseif ($script:EditorSeenOpen) { $editorOpened = $true }

## Verification run

```
PASS connect.ps1 no smart/curly quotes
PASS connect.ps1 parses cleanly
PASS git-mode.ps1 parses cleanly
PASS banner increments
PASS banner DROP>=6
PASS no_proc DROP>=6
PASS ensure reseed
PASS no bg_alive softfail wipe
connect_sticky_elseif=False
connect_seen_clear=True
```

## Out of scope

- No claude-server / sudo-from-laptop deploy
- No git commit
