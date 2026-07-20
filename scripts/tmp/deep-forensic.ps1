$ErrorActionPreference = 'Continue'
Write-Host '=== Stop-RemoteEditor extract ==='
$f = 'scripts/client/editor-launch.ps1'
$lines = Get-Content $f
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Stop-RemoteEditor') {
    for ($j = $i; $j -lt [Math]::Min($i + 100, $lines.Count); $j++) {
      '{0,5}|{1}' -f ($j + 1), $lines[$j]
    }
    break
  }
}
Write-Host '=== Test-RemoteEditorOnCorrectFolder ==='
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Test-RemoteEditor(OnCorrectFolder|WindowOpen|InAgentHome)') {
    for ($j = $i; $j -lt [Math]::Min($i + 50, $lines.Count); $j++) {
      '{0,5}|{1}' -f ($j + 1), $lines[$j]
      if ($j -gt $i -and $lines[$j] -match '^function ') { break }
    }
  }
}
Write-Host '=== SSH sepidz log hunt ==='
foreach ($u in @('sepidz', 'smart', 'farzadb', 'aminb')) {
  Write-Host "--- $u ---"
  $out = ssh -o BatchMode=yes -o ConnectTimeout=8 "${u}@192.168.250.70" @'
echo WHO=$(whoami)
ls -la /var/log/claude-connect 2>/dev/null | head -8
ls -la ~/.local/share/claude-connect 2>/dev/null | head -8
ls -la ~/claude-connect-logs 2>/dev/null | head -8
find ~ -maxdepth 3 -name '*connect*.log' 2>/dev/null | head -15
find /tmp -maxdepth 2 -name '*connect*' 2>/dev/null | head -10
ss -lntp 2>/dev/null | grep -E '2100[0-9]' || netstat -lntp 2>/dev/null | grep 2100
'@ 2>&1
  $out | Select-Object -First 35
}
