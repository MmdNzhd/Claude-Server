function Escape-BashSingleQuoted([string]$Text) { return $Text -replace "'", "'\''" }
$remote = @(
  'set +e'
  "CLEAR='0'"
  "PREFER='frontend'"
  "LU='f.bahadorifar'"
  "PORT='21006'"
  "MODE='off'"
  'AM=""'
  'if [ "$CLEAR" = "1" ]; then AM=""'
  'elif [ -n "$PREFER" ]; then AM="$PREFER"'
  'else AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)'
  'fi'
  'printf "LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n" "$LU" "$PORT" "$MODE" "$AM"'
  'echo EXIT_AM=$AM'
) -join '; '
$escaped = Escape-BashSingleQuoted $remote
$remoteCmd = "timeout 45 bash -lc '$escaped'"
Write-Output "=== RUN VIA SSH like SshX ==="
ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 $remoteCmd
Write-Output "EXIT=$LASTEXITCODE"

Write-Output "=== FIXED with single-quoted empties + no nested double quotes ==="
$remote2 = @(
  'set +e'
  "CLEAR='0'"
  "PREFER='frontend'"
  "LU='f.bahadorifar'"
  "PORT='21006'"
  "MODE='off'"
  "AM=''"
  'if [ "$CLEAR" = 1 ]; then AM='
  "AM=''"
  'elif [ -n "$PREFER" ]; then AM=$PREFER'
  'else AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)'
  'fi'
) 
# Better fixed version - write clean bash without broken then/AM split
$remote3 = @'
set +e
CLEAR=0
PREFER=frontend
LU=f.bahadorifar
PORT=21006
MODE=off
if [ "$CLEAR" = 1 ]; then
  AM=
elif [ -n "$PREFER" ]; then
  AM=$PREFER
else
  AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf "ACTIVE_MOUNT=%s\n" "$AM"
echo OK_AM=$AM
'@
# Use base64 to avoid all quoting hell
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote3))
ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
Write-Output "B64_EXIT=$LASTEXITCODE"
