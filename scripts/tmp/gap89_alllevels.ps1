$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
$sid='45c2722335a7'
# Include TRACE between mount end and MOUNT_RAW
$lines=Get-Content $today | Where-Object { $_ -match "\[$sid\]" }
$in=$false
foreach($l in $lines){
  if($l -match 'STEP end: Mounting'){ $in=$true; Write-Host $l; continue }
  if($in){
    Write-Host $l.Substring(0,[Math]::Min(260,$l.Length))
    if($l -match 'MOUNT_RAW'){ break }
  }
}
