$ErrorActionPreference='Continue'
$remote = @'
echo sepidz@Admin | sudo -S -p '' true
V=$(cat /usr/local/share/claude-client/connect-version.txt)
echo VERSION=$V
for p in RECOVERY_SKIP_CLEAR_MOUNT FINALLY_KEEP_TUNNEL EditorSeenOpen TunnelSoftFailCount no_proc_tcp_open Push-ServerConnectConf; do
  echo "PAT:$p"
  grep -RInF "$p" /usr/local/share/claude-client --include='*.ps1' --include='*.sh' 2>/dev/null | head -8
done
echo '--- PushConf snippet ---'
grep -nF 'Push-ServerConnectConf' -n /usr/local/share/claude-client/git-mode.ps1 2>/dev/null | head
grep -n 'AM=' /usr/local/share/claude-client/git-mode.ps1 2>/dev/null | head -30
'@
ssh -n -o BatchMode=yes -o ConnectTimeout=20 -o IdentityAgent=none sepidz@192.168.250.70 $remote
