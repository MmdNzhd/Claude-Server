$ErrorActionPreference='Continue'
$users = @('aminb','farzadb','hosseinb','smart','zahrak')
foreach ($u in $users) {
  Write-Output "==== USER $u ===="
  $cmd = @"
echo 'sepidz@Admin' | sudo -S -p '' bash -lc 'f=/home/$u/.claude/logs/connect-20260719.log; [ -f \$f ] || { echo NO_LOG; exit 0; }; echo SIZE=\$(stat -c%s \$f); echo VER_STARTS=\$(grep -c "session start v" \$f); echo SYNTAX=\$(grep -c "syntax error near unexpected token" \$f); echo CLEAR=\$(grep -c "CLEAR_MOUNT project=" \$f); echo DAD=\$(grep -c "keychar=ض" \$f); echo QUIT_Q=\$(grep -c "session_key=action=q" \$f); echo UPDATE26=\$(grep -c "20260719.26" \$f); echo UPDATE24=\$(grep -c "20260719.24" \$f); echo AM_MIS=\$(grep -c "ACTIVE_MOUNT server_conf=" \$f); echo SOFT=\$(grep -c soft_fail \$f); echo RECSKIP=\$(grep -c RECOVERY_SKIP_CLEAR_MOUNT \$f); echo LAST=\$(tail -n 1 \$f | cut -c1-160)'
"@
  ssh -n -o BatchMode=yes -o ConnectTimeout=25 -o IdentityAgent=none sepidz@192.168.250.70 $cmd
}
