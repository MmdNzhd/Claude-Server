# V7 DONE

Agent: V7
File: scripts/client/git-mode.sh only
Deploy: none

## begin_connect_recovery

- On trigger=auto only: calls invoke_connect_silent_update_check when declared (declare -F guard).
- trigger=manual does not call silent update check.
- Placed after RECOVERY_BEGIN log, before RECOVERY_STATE_RESET log.
- Errors from silent update are swallowed (|| true) so recovery continues.

## TUNNEL_DROP log enrichment (optional)

- no_ssh_proc_tcp_open_budget: added count=$_TUNNEL_SOFT_FAIL_COUNT; reset moved after log.
- bg_alive_forward_dead: added banner=${_TUNNEL_BANNER_CACHE_BANNER:-} for Windows parity.
- Other TUNNEL_DROP lines already had count/threshold fields.

## Dependencies

- invoke_connect_silent_update_check is defined in connect-ui.sh (sourced by connect launchers).
- Mac connect.sh calls begin_connect_recovery auto/manual with same trigger names as Windows.
