$ErrorActionPreference='Continue'
$big='D:\Smart\Claude-Code-Server\scripts\tmp\sepidz-smart-connect-20260719.log'
$fz='D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'

'=== BIG LOG: Unexpected / AA616 / ERROR counts ==='
Select-String -Path $big -Pattern 'Unexpected error|AA616|Agent Execution|Connection Error|Remove-Item' |
  Group-Object { if ($_.Line -match 'AA616'){'AA616'} elseif ($_.Line -match 'Unexpected'){'Unexpected'} else {'Other'} } |
  ForEach-Object { "$($_.Name)=$($_.Count)" }

'=== BIG: last Unexpected ==='
Select-String -Path $big -Pattern 'Unexpected error' | Select-Object -Last 15 | ForEach-Object {
  $_.Line.Substring(0,[Math]::Min(280,$_.Line.Length))
}

'=== BIG: AA616 samples ==='
Select-String -Path $big -Pattern 'AA616' | Select-Object -Last 10 | ForEach-Object {
  $_.Line.Substring(0,[Math]::Min(280,$_.Line.Length))
}

'=== BIG: session starts by version (tail users) ==='
Select-String -Path $big -Pattern 'session start v' | Select-Object -Last 25 | ForEach-Object {
  if ($_.Line -match 'session start (v\S+) user=(\S+)') { "$($Matches[1]) $($Matches[2])" } else { $_.Line.Substring(0,120) }
}

'=== BIG: AUTH failures ==='
Select-String -Path $big -Pattern 'AUTH_SYNC: result.*ok=False|AUTH.*fail|STEP end: Syncing Cursor auth fail' |
  Select-Object -Last 20 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(260,$_.Line.Length)) }

'=== FARZAD: versions used ==='
Select-String -Path $fz -Pattern 'session start v' | ForEach-Object {
  if ($_.Line -match 'session start (v\S+)') { $Matches[1] }
} | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" }

'=== FARZAD: soft_fail / TUNNEL_DROP ==='
@(
  (Select-String -Path $fz -Pattern 'soft_fail').Count
  (Select-String -Path $fz -Pattern 'TUNNEL_DROP').Count
  (Select-String -Path $fz -Pattern 'elif').Count
) | ForEach-Object { $_ }
"soft_fail=$((Select-String -Path $fz -Pattern 'soft_fail').Count) TUNNEL_DROP=$((Select-String -Path $fz -Pattern 'TUNNEL_DROP').Count) elif_syntax=$((Select-String -Path $fz -Pattern 'unexpected token ``elif').Count)"
