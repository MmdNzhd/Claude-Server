$ErrorActionPreference = 'Continue'
$out = ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 @'
echo VER=$(cat /usr/local/share/claude-client/connect-version.txt)
echo LAYOUT:
ls -la /usr/local/share/claude-client | head -40
echo MANIFEST_SIDECAR:
grep -i sidecar /usr/local/share/claude-client/manifest.txt || echo NONE
echo MANIFEST_HEAD:
head -30 /usr/local/share/claude-client/manifest.txt
echo HAS_UPDATE_BUG:
grep -n UpdateEndpointTarget /usr/local/share/claude-client/connect-update.ps1 || echo no_var_in_bundle
grep -n UpdateEndpointTarget /usr/local/share/claude-client/windows/connect-update.ps1 2>/dev/null || true
'@
$out
