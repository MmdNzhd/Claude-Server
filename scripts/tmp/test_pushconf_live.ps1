$ErrorActionPreference='Continue'
$Alias='claude-server-sepidz'

function Escape-BashSingleQuoted([string]$Text) {
    return $Text -replace "'", "'\''"
}

function SshRaw([string]$Cmd) {
  Write-Host "=== RAW try ==="
  Write-Host ("cmd first 180: " + $Cmd.Substring(0,[Math]::Min(180,$Cmd.Length)))
  $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 $Alias $Cmd 2>&1
  Write-Host ("exit=$LASTEXITCODE out=$($out -join ' | ')")
}

function SshWrapped([string]$Cmd) {
  $escaped = Escape-BashSingleQuoted $Cmd
  $remoteCmd = "timeout 45 bash -lc '$escaped'"
  Write-Host "=== WRAPPED try ==="
  Write-Host ("wrapped first 200: " + $remoteCmd.Substring(0,[Math]::Min(200,$remoteCmd.Length)))
  $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 $Alias $remoteCmd 2>&1
  Write-Host ("exit=$LASTEXITCODE out=$($out -join ' | ')")
}

# 1) Simple
SshWrapped 'echo OK_SIMPLE'

# 2) Probe (foreign session) - known failing pattern
$probeCmd = 'set +e; CONF="$HOME/.claude-connect.conf"; LU=""; OS=""; PORT=""; if [ -f "$CONF" ]; then LU=$(grep -E "^LAPTOP_USER=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); OS=$(grep -E "^LAPTOP_OS=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); PORT=$(grep -E "^TUNNEL_PORT=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s\nOS=%s\nPORT=%s\n" "$LU" "$OS" "$PORT"'
SshWrapped $probeCmd

# 3) Probe rewritten with only single quotes
$probe2 = 'set +e; CONF=$HOME/.claude-connect.conf; LU=; OS=; PORT=; if [ -f "$CONF" ]; then LU=$(grep -E "^LAPTOP_USER=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); OS=$(grep -E "^LAPTOP_OS=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); PORT=$(grep -E "^TUNNEL_PORT=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s\nOS=%s\nPORT=%s\n" "$LU" "$OS" "$PORT"'
# still has double quotes...
$probe3 = @'
set +e
CONF=$HOME/.claude-connect.conf
LU=
OS=
PORT=
if [ -f "$CONF" ]; then
  LU=$(grep -E '^LAPTOP_USER=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
  OS=$(grep -E '^LAPTOP_OS=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
  PORT=$(grep -E '^TUNNEL_PORT=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf 'LU=%s\nOS=%s\nPORT=%s\n' "$LU" "$OS" "$PORT"
'@ -replace "`r?`n", '; '
Write-Host "`n=== probe3 (mixed) ==="
SshWrapped $probe3

# 4) base64 approach
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($probeCmd))
$b64cmd = "echo $b64 | base64 -d | bash"
Write-Host "`n=== base64 ==="
SshRaw $b64cmd

# 5) Push conf style with single-quote only vars
$push = @'
set +e
CLEAR=0
PREFER=
LU=Smart
PORT=21002
MODE=hide
AM=
if [ "$CLEAR" = "1" ]; then AM=
elif [ -n "$PREFER" ]; then AM=$PREFER
else AM=$(grep -E '^ACTIVE_MOUNT=' $HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf 'GOT LU=%s PORT=%s MODE=%s AM=%s\n' "$LU" "$PORT" "$MODE" "$AM"
'@ -replace "`r?`n", '; '
Write-Host "`n=== push style ==="
SshWrapped $push
