$ErrorActionPreference='Continue'
$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
$lines = Get-Content $log

Write-Output '==== Who calls banner so often? counts per minute ===='
$byMin = @{}
foreach ($ln in $lines) {
  if ($ln -match '\[DEBUG\] GITMODE: TUNNEL_BANNER port=') {
    if ($ln -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})') {
      $m=$matches[1]
      if (-not $byMin.ContainsKey($m)) { $byMin[$m]=0 }
      $byMin[$m]++
    }
  }
}
$byMin.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0}  count={1}" -f $_.Name, $_.Value } | Select-Object -First 40
Write-Output '...'
$byMin.GetEnumerator() | Sort-Object Name | Select-Object -Last 10 | ForEach-Object { "{0}  count={1}" -f $_.Name, $_.Value }

Write-Output ''
Write-Output '==== Call sites: lines before TUNNEL_BANNER_BEGIN (unique neighbors) ===='
$prevKinds = @{}
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -notmatch 'TUNNEL_BANNER_BEGIN') { continue }
  $prev = ''
  for ($j=$i-1; $j -ge [Math]::Max(0,$i-5); $j--) {
    if ($lines[$j] -match 'GITMODE: (\S+)|PERF\[(\w+)\]|VERDICT|DIAG|SSH_BEGIN cmd=(.{0,60})') {
      $prev = $lines[$j] -replace '^\[.*?\]\s*\[.*?\]\s*',''
      $prev = $prev.Substring(0, [Math]::Min(90,$prev.Length))
      break
    }
  }
  if (-not $prevKinds.ContainsKey($prev)) { $prevKinds[$prev]=0 }
  $prevKinds[$prev]++
}
$prevKinds.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { "{0,5}  {1}" -f $_.Value, $_.Key }

Write-Output ''
Write-Output '==== Drop1 (17:05:22): was tunnel process alive? ===='
for ($i=200; $i -le 235; $i++) { if ($i-1 -lt $lines.Count) { $lines[$i-1] } }
Write-Output '--- look for pid 38352 death ---'
Select-String -Path $log -Pattern '38352|pid=38352|TUNNEL_STOP|HasExited|bg_alive' |
  Where-Object { $_.LineNumber -le 250 } |
  ForEach-Object { "L$($_.LineNumber): $($_.Line)" }

Write-Output ''
Write-Output '==== Drop2 context: 30s probe schedule ===='
for ($i=12500; $i -le 12525; $i++) { $lines[$i-1] }
Write-Output '--- LastForwardProbe / TUNNEL_DROP ---'
Select-String -Path $log -Pattern 'TUNNEL_DROP|LastForward|bg_alive_forward' | ForEach-Object { $_.Line }

Write-Output ''
Write-Output '==== Drop3: why ssh_died after respawn ===='
for ($i=92105; $i -le 92175; $i++) { $lines[$i-1] }

Write-Output ''
Write-Output '==== Diagnostic tunnel check vs reality ===='
Select-String -Path $log -Pattern 'TUNNEL_DOWN|tunnel.*banner|Reverse tunnel|21003' |
  Where-Object { $_.Line -match 'VERDICT|DIAG|ERROR|WARN' } |
  Select-Object -First 30 |
  ForEach-Object { $_.Line }
