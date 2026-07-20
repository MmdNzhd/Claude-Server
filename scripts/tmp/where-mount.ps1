foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  Write-Host "==== $t ===="
  & ssh -o BatchMode=yes -o ConnectTimeout=10 $t "command -v claude-mount; ls -la /usr/local/bin/claude-mount /usr/local/lib/claude-mount /usr/local/lib/claude-server/claude-mount.sh 2>&1 | head -10; grep -l GIT_MODE /usr/local/bin/claude-mount /usr/local/lib/claude* 2>/dev/null | head"
}
