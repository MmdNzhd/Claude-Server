set -e
ok=0; bad=0
check() { if eval "$2"; then echo "OK $1"; ok=$((ok+1)); else echo "BAD $1"; bad=$((bad+1)); fi; }
check win_ia "grep -q IdentityAgent=none scripts/client/windows/connect-update.ps1"
check win_swap "grep -q Swap-LiveDir scripts/client/windows/connect-update.ps1"
check win_sum "grep -q Test-BundleChecksums scripts/client/windows/connect-update.ps1"
check mac_ia "grep -q IdentityAgent=none scripts/client/mac/connect-update.sh"
check mac_to "grep -q _run_timed scripts/client/mac/connect-update.sh"
check mac_swap "grep -q _swap_dir scripts/client/mac/connect-update.sh"
check bat_depth "grep -q CLAUDE_CONNECT_UPDATE_DEPTH scripts/client/windows/connect.bat"
check mac_depth "grep -q CLAUDE_CONNECT_UPDATE_DEPTH scripts/client/mac/connect.sh"
check dcb_stage "grep -q STAGE_BUNDLE scripts/server/commands/deploy-client-bundle.sh"
check dcb_sum "grep -q checksums.txt scripts/server/commands/deploy-client-bundle.sh"
check upd_ver "grep -q VERIFY_OK scripts/server/commands/update-server.sh"
check pub_bom "grep -q 'UTF8Encoding]::new(\$false)' publish/deploy-client-bundles.ps1"
echo "ok=$ok bad=$bad"
[ "$bad" -eq 0 ]
