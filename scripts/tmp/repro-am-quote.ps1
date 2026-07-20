$remote = @(
  'set +e'
  "CLEAR='0'"
  "PREFER='frontend'"
  'AM=""'
  'if [ "$CLEAR" = "1" ]; then AM=""'
  'elif [ -n "$PREFER" ]; then AM="$PREFER"'
  'else AM=keep'
  'fi'
) -join '; '
Write-Output "REMOTE=$remote"
# simulate double-quote wrap like ssh "cmd"
$wrapped = '"' + $remote + '"'
Write-Output "WRAPPED_LEN=$($wrapped.Length)"
# Show what happens if ExpandString
try {
  $expanded = $ExecutionContext.InvokeCommand.ExpandString($remote)
  Write-Output "EXPANDED=$expanded"
} catch { Write-Output "EXPAND_ERR=$($_.Exception.Message)" }
