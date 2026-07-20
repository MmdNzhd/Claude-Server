function Run-Ssh([string]$Target,[string]$Cmd){
  $args=@('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',$Target,$Cmd)
  $out=Join-Path $env:TEMP 'full2-out.txt'; $err=Join-Path $env:TEMP 'full2-err.txt'
  $p=Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  (Get-Content $out -Raw -EA SilentlyContinue)
}
Write-Output '=== SEPIDZ LAYOUT + MARKERS ==='
Run-Ssh 'claude-server-sepidz' @'
find /usr/local/share/claude-client -maxdepth 2 -type f \( -name "*.ps1" -o -name "*.sh" -o -name "connect-version.txt" \) | sort
echo "---"
# windows files may be at root of bundle
for f in connect.ps1 git-mode.ps1 connect-ui.ps1 mac/connect.sh mac/git-mode.sh git-mode.sh; do
  p=/usr/local/share/claude-client/$f
  if [ -f "$p" ]; then echo "HAS $f"; else echo "MISS $f"; fi
done
echo "--- markers ---"
grep -n "PUSH_CONF_RESULT\|useVk\|skip_duplicate\|SESSION_KEY ignore\|_action=\"\"\|soft_fail count=.*/6\|ORPHAN_TUNNEL: skip_current\|IdentityAgent" \
  /usr/local/share/claude-client/connect.ps1 \
  /usr/local/share/claude-client/git-mode.ps1 \
  /usr/local/share/claude-client/mac/connect.sh \
  /usr/local/share/claude-client/mac/git-mode.sh \
  /usr/local/share/claude-client/git-mode.sh 2>/dev/null | head -50
'@
Write-Output '=== TESTS LAST KNOWN ==='
Write-Output 'pipeline+deep were green after assert updates'
