function Escape-BashSingleQuoted([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s -replace "'", "'\''")
}
$clearFlag='0'; $preferEsc=''; $lu='Smart'; $portEsc='21002'; $modeEsc='hide'
$remote = @(
  'set +e'
  "CLEAR='$clearFlag'"
  "PREFER='$preferEsc'"
  "LU='$lu'"
  "PORT='$portEsc'"
  "MODE='$modeEsc'"
  'AM=""'
  'if [ "$CLEAR" = "1" ]; then AM=""'
  'elif [ -n "$PREFER" ]; then AM="$PREFER"'
  'else AM=$(grep -E "^ACTIVE_MOUNT=" "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)'
  'fi'
  'mkdir -p "$HOME/.local/bin"'
  'printf "LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n" "$LU" "$PORT" "$MODE" "$AM" > "$HOME/.claude-connect.conf"'
  'chmod 600 "$HOME/.claude-connect.conf" 2>/dev/null || true'
  'true'
) -join '; '
Write-Host "RAW len=$($remote.Length)"
Write-Host $remote.Substring(0,[Math]::Min(300,$remote.Length))
$escaped = Escape-BashSingleQuoted $remote
$wrapped = "timeout 45 bash -lc '$escaped'"
Write-Host "`nWRAPPED len=$($wrapped.Length)"
Write-Host $wrapped.Substring(0,[Math]::Min(400,$wrapped.Length))
# Write to temp and test via WSL or git-bash if available
$tmp = Join-Path $env:TEMP 'pushconf-test.sh'
Set-Content -Path $tmp -Value $remote -Encoding ASCII -NoNewline
Write-Host "`nWrote $tmp"
