$ErrorActionPreference = 'Stop'
$c = Get-Content 'scripts\client\windows\connect.ps1' -Raw

function Show-Around([string]$label, [string]$needle, [int]$before=5, [int]$after=40) {
  $idx = $c.IndexOf($needle)
  Write-Host "==== $label idx=$idx ===="
  if ($idx -lt 0) { return }
  # line-based
  $lines = $c -split "`r?`n"
  $li = 0; $pos=0
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($pos + $lines[$i].Length -ge $idx) { $li=$i; break }
    $pos += $lines[$i].Length + 1
  }
  $s = [Math]::Max(0, $li-$before)
  $e = [Math]::Min($lines.Count-1, $li+$after)
  for ($i=$s; $i -le $e; $i++) { Write-Host ('{0,5}|{1}' -f ($i+1), $lines[$i]) }
}

Show-Around 'Invoke-SshXCore' 'function Invoke-SshXCore' 0 50
Show-Around 'Complete-PostTunnelRecovery' 'function Complete-PostTunnelRecovery' 0 80
Show-Around 'auto recovery window' 'RECOVERY_SKIP_CLEAR_MOUNT' 30 40
Show-Around 'auto_relaunch' 'auto_relaunch' 5 40
Show-Around 'hard refuse' 'hard-refuse' 5 30
Show-Around 'sepidz path' 'sepidz' 2 20
