$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$winGit = Join-Path $Root 'scripts\client\git-mode.ps1'
$macGit = Join-Path $Root 'scripts\client\git-mode.sh'
Write-Host "exists=$(Test-Path $winGit)"
$r = Select-String -LiteralPath $winGit -Pattern 'TunnelSoftFailCount -lt 6' -SimpleMatch
Write-Host "select_count=$($r.Count)"
if ($r) { $r | ForEach-Object { Write-Host "HIT L$($_.LineNumber): $($_.Line)" } }
$raw = Get-Content $winGit -Raw
Write-Host ("raw_match=" + ($raw -match 'TunnelSoftFailCount -lt 6'))
# Ensure hits
Select-String -LiteralPath $winGit -Pattern 'ENSURE_TUNNEL soft_fail' | ForEach-Object { Write-Host "ENS L$($_.LineNumber): $($_.Line.Trim())" }
Select-String -LiteralPath $winGit -Pattern 'banner_miss_tcp_open' | ForEach-Object { Write-Host "BAN L$($_.LineNumber): $($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))" }
# wait_for body via brace count
$mac = Get-Content $macGit
$i = ($mac | Select-String -Pattern '^wait_for_tunnel_up\(\)').LineNumber - 1
$depth = 0; $start = $i; $end = $i
for ($j = $i; $j -lt $mac.Count; $j++) {
  $depth += ([regex]::Matches($mac[$j], '\{')).Count
  $depth -= ([regex]::Matches($mac[$j], '\}')).Count
  $end = $j
  if ($j -gt $i -and $depth -le 0) { break }
}
$wf = $mac[$start..$end] -join "`n"
Write-Host "WAIT_BODY:"
Write-Host $wf
Write-Host ("seq12=" + ($wf -match 'seq\s+1\s+12') + " le12=" + ($wf -match '-le\s+12'))
# recover brace
$i = ($mac | Select-String -Pattern '^recover_mounts_if_needed\(\)').LineNumber - 1
$depth = 0; $start = $i; $end = $i
for ($j = $i; $j -lt $mac.Count; $j++) {
  $depth += ([regex]::Matches($mac[$j], '\{')).Count
  $depth -= ([regex]::Matches($mac[$j], '\}')).Count
  $end = $j
  if ($j -gt $i -and $depth -le 0) { break }
}
Write-Host "RECOVER_BODY:"
Write-Host ($mac[$start..$end] -join "`n")
