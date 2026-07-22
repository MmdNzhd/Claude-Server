$day = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$since = (Get-Date).AddMinutes(-40)
function Parse-Ts([string]$line) {
  if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
    try { return [datetime]::ParseExact($Matches[1],'yyyy-MM-dd HH:mm:ss',$null) } catch { return $null }
  }
  return $null
}
Write-Host ("NOW="+(Get-Date).ToString('HH:mm:ss')+" SINCE="+$since.ToString('HH:mm:ss'))
$err=@(); $warn=@(); $start=@(); $notable=@()
Get-Content $day -Encoding UTF8 | ForEach-Object {
  $ts = Parse-Ts $_
  if ($null -eq $ts -or $ts -lt $since) { return }
  if ($_ -match '\[ERROR\]|\[FATAL\]') { $err += $_ }
  elseif ($_ -match '\[WARN\]') { $warn += $_ }
  if ($_ -match 'session start|LAUNCH_KILL|preserved_open|Opening Cursor|UPDATE:|PROC_START_FAIL|AUTH ERROR|CURSOR_PROXY') { $notable += $_ }
}
Write-Host ("smart_recent warn=$($warn.Count) err=$($err.Count) notable=$($notable.Count)")
Write-Host '--- ERR ---'
$err | Select-Object -Last 15 | ForEach-Object { $_.Substring(0,[Math]::Min(220,$_.Length)) }
Write-Host '--- WARN ---'
$warn | Select-Object -Last 20 | ForEach-Object { $_.Substring(0,[Math]::Min(220,$_.Length)) }
Write-Host '--- NOTABLE ---'
$notable | Select-Object -Last 25 | ForEach-Object { $_.Substring(0,[Math]::Min(220,$_.Length)) }
