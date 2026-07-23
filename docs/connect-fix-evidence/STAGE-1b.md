# STAGE-1b Evidence Pack

## ID
- Stage: 1b (CRLF-sanitize SSH remote bash)
- CONNECT_VERSION: `20260722.40`
- Timestamp: 2026-07-22T17:20Z approx
- deploy_ran=no

## VERIFY
- Live log: session `48959888542e` @ 16:22 — `syntax error near unexpected token $'do\r'` on `for p in 20026 20027; do` (Acquire batch open-ports probe).
- Code anchor: `Get-ServerOpenTunnelPorts` here-string `for p in $list; do` → `SshX $script`; `Invoke-SshXCore` base64-pipes to remote bash.
- still_live=yes in historical log; post-patch requires Connect relaunch for LIVE absence.

## RESEARCH
1. https://www.gnu.org/software/bash/manual/html_node/ANSI_002dC-Quoting.html — `$'…\r'` ANSI-C quoting explains the token form
2. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-7.6 — here-strings preserve newlines (CRLF on Windows)
3. https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sh.html — shell grammar; CR is not a valid token separator like LF

What this changes:
- Strip CR in `Invoke-SshXCore` before Base64 (all Connect SSH remotes)
- Defense: LF-normalize `$script` in `Get-ServerOpenTunnelPorts` before `SshX`

What we will NOT do:
- Change port formula / MaxStartups; not rewrite probes to avoid `for` loops

## RED_TEST
```
powershell -File scripts/client/tests/test-ssh-remote-bash-lf-only.ps1
# Failed: Invoke-SshXCore strips CR LF / before ToBase64String / Get-ServerOpenTunnelPorts normalize
```

## IMPLEMENT
- `scripts/client/windows/connect.ps1` `Invoke-SshXCore`: `$RemoteCmd` CR→LF before `ToBase64String`
- `scripts/client/git-mode.ps1` `Get-ServerOpenTunnelPorts`: sanitize `$script` before `SshX`
- Test: `test-ssh-remote-bash-lf-only.ps1` (+ run-all register)
- drive_by=none

## GREEN_TEST
```
test-ssh-remote-bash-lf-only.ps1 → Passed: 8 Failed: 0
test-acquire-tunnel-port-no-port-alias.ps1 → still Passed: 10 (no regress)
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need new Connect from Desktop\Claude-Connect so Acquire probe runs through patched Invoke-SshXCore`
- Expected after relaunch: no `$'do\r'` in SSH_END WARN for port for-loops.

## GATE
`STAGE_1b_DONE` 2026-07-22T17:20Z `deploy_ran=no` N+1 unlocked (Stage 2)
