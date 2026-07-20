$ErrorActionPreference='Continue'
Write-Output '=== VERSION ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt; echo; wc -l /usr/local/share/claude-client/manifest.txt; head -5 /usr/local/share/claude-client/manifest.txt"
Write-Output '=== FIX STRINGS in deployed connect.ps1 / git-mode.ps1 ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' bash -lc 'grep -nE \"RECOVERY_SKIP_CLEAR_MOUNT|FINALLY_KEEP_TUNNEL|EditorSeenOpen|TunnelSoftFailCount|no_proc_tcp_open\" /usr/local/share/claude-client/connect.ps1 /usr/local/share/claude-client/git-mode.ps1 2>/dev/null | head -40'"
Write-Output '=== SMART still frozen ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt; hostname"
