$lines = Get-Content scripts/client/git-mode.ps1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'Write-GitModeLog') {
    $chunk = $lines[$i]
    if ($i + 1 -lt $lines.Count) { $chunk += ' ' + $lines[$i+1] }
    if ($chunk -notmatch "'(INFO|WARN|ERROR|DEBUG|TRACE)'") {
      '{0}:{1}' -f ($i+1), $lines[$i].Trim()
    }
  }
}
