$path = 'D:\Smart\Claude-Code-Server\scripts\tmp\BUGS-SERIOUS-20260720.md'
$add = @'

### Tunnel/session ([Tunnel session bugs](174fa2c0-eab1-4719-99f8-6f3a33ab60a4))

| # | Slug | Sev | Conf | Problem |
|---|------|-----|------|---------|
| 75 | `mac-recover-quote-mangle` | P0 | 5 | Mac `recover_mounts_if_needed` quote-mangles remote cmd; fallbacks call missing server `sshx`; UI still says Recover done |
| 76 | `mac-tunnel-wait-4-vs-win-12` | P0 | 5 | Mac tunnel wait loops 4× while UI says N/12; Win waits 12 — spurious tunnel-up fail on Mac |
| 77 | `banner-miss-tcp-softfail-never-drops` | P1 | 5 | `banner_miss_tcp_open` never budgets/DROPs — zombie forward looks healthy forever |
| 78 | `ensure-reuses-zombie-on-banner-miss` | P1 | 5 | Ensure returns success / TUNNEL_REUSED on banner miss + TCP open |
| 79 | `editor-seen-sticky-skips-mount-clear` | P1 | 5 | After editor closed, sticky EditorSeenOpen still skipRecoveryClear → stale mount preserved |
| 80 | `win-sticky-forces-editorOpened` | P1 | 5 | Win forces editorOpened=true from sticky even when not on-folder |
| 81 | `mac-abort-no-clear-active-mount` | P1 | 5 | Mac abort clears local ACTIVE_MOUNT_ID but PushConf without --clear |
| 82 | `mac-post-recover-pid-only` | P1 | 5 | Mac post-recover checks PID only; Win checks Test-TunnelUp banner |
| 83 | `mac-fallthrough-skips-recovery-policy` | P1 | 4 | Mac fallthrough `r` can skip preserve/clear recovery block |
| 84 | `win-softfail-budget-no-hard-return` | P1 | 4 | Win soft_fail ≥6 does not hard-return unlike Mac TUNNEL_DROP |

Updated open serious ≈ **80+** (was ~70+). Tunnel agent complete.
'@

# Mark tunnel complete in Agents section
$c = Get-Content -Raw $path
$c = $c -replace '- tunnel \(in progress / incomplete at merge time\)', '- tunnel — completed ([Tunnel session bugs](174fa2c0-eab1-4719-99f8-6f3a33ab60a4))'
# Avoid double-append
if ($c -notmatch 'mac-recover-quote-mangle') {
  $c = $c.TrimEnd() + "`n" + $add + "`n"
}
Set-Content -Path $path -Value $c -Encoding UTF8
'appended ok'
Select-String -Path $path -Pattern 'mac-recover-quote-mangle|Tunnel session' | Select-Object -First 5
