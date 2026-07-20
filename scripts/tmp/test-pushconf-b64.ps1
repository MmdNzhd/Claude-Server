$ErrorActionPreference='Stop'
# Simulate variable expansion of remoteBody
$clearFlag='0'; $preferEsc='frontend'; $lu='farzadb'; $portEsc='21006'; $modeEsc='off'
$remoteBody = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
LU='$lu'
PORT='$portEsc'
MODE='$modeEsc'
if [ "`$CLEAR" = "1" ]; then
  AM=
elif [ -n "`$PREFER" ]; then
  AM=`$PREFER
else
  AM=`$(grep -E '^ACTIVE_MOUNT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s\n' "`$CLEAR" "`$PREFER" "`$AM"
"@
Write-Output '--- expanded body ---'
Write-Output $remoteBody
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
$out = ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 "echo $b64 | base64 -d | bash" 2>&1
Write-Output $out
Write-Output "EXIT=$LASTEXITCODE"
