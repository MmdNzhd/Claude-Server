$ErrorActionPreference='Continue'
function Test-NopasswdInstall([string]$Label,[string]$Target) {
  Write-Host "==== $Label sudo -n install path ===="
  $cmd = @'
set +e
echo "who=$(whoami) home=$HOME"
echo "sudoers_readable=$(sudo -n cat /etc/sudoers.d/claude-client-deploy 2>/dev/null | wc -l)"
sudo -n cat /etc/sudoers.d/claude-client-deploy 2>/dev/null || echo 'cannot read sudoers with sudo -n cat'
# exact command used by deploy
if sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh --help >/dev/null 2>&1; then
  echo INSTALL_NOPASSWD=yes
else
  # install script needs a zip arg; test permission with a dry run that will fail on missing zip but prove sudo -n works
  out=$(sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh /tmp/does-not-exist.zip 2>&1)
  ec=$?
  echo "dry_exit=$ec"
  echo "$out" | head -5
  if echo "$out" | grep -qi 'password'; then echo INSTALL_NOPASSWD=no_password_prompt; else echo INSTALL_NOPASSWD=likely_yes_or_script_fail; fi
fi
echo VER=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
'@
  $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
  & ssh -o BatchMode=yes -o ConnectTimeout=15 $Target "echo $b64 | base64 -d | bash"
}
Test-NopasswdInstall 'Smart' 'smart@192.168.210.240'
Test-NopasswdInstall 'Sepidz' 'sepidz@192.168.250.70'
