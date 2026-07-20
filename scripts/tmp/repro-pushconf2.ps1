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
  'printf "ACTIVE=%s\n" "$AM"'
) -join '; '
$escaped = Escape-BashSingleQuoted $remote
$remoteCmd = "timeout 45 bash -lc '$escaped'"
Write-Output '--- current SshX style ---'
$out = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 $remoteCmd 2>&1
Write-Output $out
Write-Output "EXIT=$LASTEXITCODE"

# Fix: base64 payload (no nested quotes in ssh cmdline)
$script = @"
set +e
CLEAR='$('0')'
PREFER='frontend'
LU='f.bahadorifar'
PORT='21006'
MODE='off'
if [ "`$CLEAR" = "1" ]; then
  AM=""
elif [ -n "`$PREFER" ]; then
  AM="`$PREFER"
else
  AM=`$(grep -E '^ACTIVE_MOUNT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' "`$LU" "`$PORT" "`$MODE" "`$AM" > "`$HOME/.claude-connect.conf.test"
printf 'OK AM=%s\n' "`$AM"
cat "`$HOME/.claude-connect.conf.test"
"@
# Build without PS expansion issues - use single-quoted here-string
$script = @'
set +e
CLEAR='0'
PREFER='frontend'
LU='testuser'
PORT='21006'
MODE='off'
if [ "$CLEAR" = "1" ]; then
  AM=""
elif [ -n "$PREFER" ]; then
  AM="$PREFER"
else
  AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf "OK AM=%s\n" "$AM"
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
Write-Output '--- base64 style ---'
$out2 = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 "echo $b64 | base64 -d | bash" 2>&1
Write-Output $out2
Write-Output "EXIT2=$LASTEXITCODE"

# Fix2: only single quotes in remote, join with newlines via printf %b
$remote4 = 'set +e; CLEAR=0; PREFER=frontend; if [ "$CLEAR" = 1 ]; then AM=; elif [ -n "$PREFER" ]; then AM=$PREFER; else AM=keep; fi; printf OK=%s\\n "$AM"'
# still has double quotes around $CLEAR
$remote5 = 'set +e; CLEAR=0; PREFER=frontend; if [ "$CLEAR" = 1 ]; then AM=; elif [ -n "$PREFER" ]; then AM=$PREFER; else AM=keep; fi; echo OK=$AM'
$esc5 = Escape-BashSingleQuoted $remote5
$cmd5 = "timeout 45 bash -lc '$esc5'"
Write-Output '--- minimal doublequotes around vars ---'
$out5 = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 $cmd5 2>&1
Write-Output $out5
Write-Output "EXIT5=$LASTEXITCODE"

# Fix3: NO double quotes at all
$remote6 = 'set +e; CLEAR=0; PREFER=frontend; if [ $CLEAR = 1 ]; then AM=; elif [ -n $PREFER ]; then AM=$PREFER; else AM=keep; fi; echo OK=$AM'
$esc6 = Escape-BashSingleQuoted $remote6
$cmd6 = "timeout 45 bash -lc '$esc6'"
Write-Output '--- zero doublequotes ---'
$out6 = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 $cmd6 2>&1
Write-Output $out6
Write-Output "EXIT6=$LASTEXITCODE"
