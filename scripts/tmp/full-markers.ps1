function Run-Ssh([string]$Target,[string]$Cmd){
  $args=@('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',$Target,$Cmd)
  $out=Join-Path $env:TEMP 'mk-out.txt'; $err=Join-Path $env:TEMP 'mk-err.txt'
  $p=Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  Get-Content $out -EA SilentlyContinue
}
Run-Ssh 'claude-server-sepidz' 'grep -c useVk /usr/local/share/claude-client/connect.ps1; grep -c PUSH_CONF_RESULT /usr/local/share/claude-client/git-mode.ps1; grep -c skip_duplicate /usr/local/share/claude-client/git-mode.ps1; grep -c SESSION_KEY /usr/local/share/claude-client/connect.ps1; grep -c soft_fail /usr/local/share/claude-client/mac/git-mode.sh; grep -c skip_current /usr/local/share/claude-client/mac/git-mode.sh; grep -c _action= /usr/local/share/claude-client/mac/connect.sh; grep -c PUSH_CONF_RESULT /usr/local/share/claude-client/mac/git-mode.sh; head -1 /usr/local/share/claude-client/connect-version.txt; grep ConnectVersion /usr/local/share/claude-client/connect.ps1 | head -1; grep CONNECT_VERSION /usr/local/share/claude-client/mac/connect.sh | head -1'
