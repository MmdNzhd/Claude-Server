$lines = Get-Content scripts\client\windows\connect.ps1
# find ControlMaster comment
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'ControlMaster|MaxSessions|cascade') {
    $a=[Math]::Max(0,$i-2); $b=[Math]::Min($lines.Count-1,$i+5)
    for ($j=$a;$j -le $b;$j++) { Write-Host ('{0,4}|{1}' -f ($j+1), $lines[$j]) }
    Write-Host '---'
  }
}
Write-Host '=== Initialize-ServerSession start (first SSH greps) ==='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'existingLu|LAPTOP_USER|Initialize-ServerSession' -Context 0,2 |
  Select-Object -First 20 | ForEach-Object { $_.Line.Trim() }
# git-mode around 810-900
Write-Host '=== git-mode Initialize around conf reads ==='
$gm=Get-Content scripts\client\git-mode.ps1
for ($i=800; $i -lt 920; $i++) { Write-Host ('{0,4}|{1}' -f ($i+1), $gm[$i]) }
