$p = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$lines = Get-Content -LiteralPath $p
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Escape-BashSingleQuoted') {
    Write-Output "START=$($i+1)"
    for ($j = $i; $j -lt [Math]::Min($i+40, $lines.Count); $j++) {
      Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
      if ($j -gt $i -and $lines[$j] -match '^function ') { break }
    }
  }
  if ($lines[$i] -match 'function Invoke-SshXCore') {
    Write-Output "CORE=$($i+1)"
    for ($j = $i; $j -lt [Math]::Min($i+60, $lines.Count); $j++) {
      Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
      if ($j -gt $i -and $lines[$j] -match '^function ') { break }
    }
  }
}

# Simulate full SshX wrap
function Escape-BashSingleQuoted([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s -replace "'", "'\''")
}
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
  'printf "LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n" "$LU" "$PORT" "$MODE" "$AM" > "$HOME/.claude-connect.conf"'
) -join '; '
$escaped = Escape-BashSingleQuoted $remote
$remoteCmd = "timeout 45 bash -lc '$escaped'"
Write-Output '=== ESCAPED REMOTE (first 500) ==='
Write-Output $escaped.Substring(0, [Math]::Min(500, $escaped.Length))
Write-Output '=== FULL bash -lc arg length ==='
Write-Output $remoteCmd.Length
# Write to temp and test via wsl or just show critical section around elif
$idx = $escaped.IndexOf('elif')
Write-Output ("AROUND_ELIF=" + $escaped.Substring([Math]::Max(0,$idx-80), [Math]::Min(200, $escaped.Length - [Math]::Max(0,$idx-80))))
Set-Content -LiteralPath 'D:\Smart\Claude-Code-Server\scripts\tmp\pushconf-repro.sh' -Value $escaped -Encoding ASCII
Write-Output 'wrote pushconf-repro.sh'
