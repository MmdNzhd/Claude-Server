$ErrorActionPreference='Continue'
$day = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host ("day size=" + (Get-Item $day).Length + " mtime=" + (Get-Item $day).LastWriteTime)
Write-Host '--- count patterns ---'
foreach ($pat in @('proxy_settings_changed','preserved_open_windows','LAUNCH_KILL: reason=','auth_relaunch soft-stop','soft-stop profile_count')) {
  $n = @(Select-String -Path $day -Pattern $pat -SimpleMatch -EA SilentlyContinue).Count
  # also regex
  $n2 = @(Select-String -Path $day -Pattern $pat -EA SilentlyContinue).Count
  Write-Host ("pat=[$pat] simple=$n regex=$n2")
}
Write-Host '--- lines containing soft-stop today afternoon ---'
Select-String -Path $day -Pattern 'soft-stop' | Where-Object { $_.Line -match '\[2026-07-21 1[4-6]:' } | ForEach-Object { $_.Line.Substring(0,[Math]::Min(240,$_.Line.Length)) }
Write-Host '--- lines 15:39 kill area (raw scan by time) ---'
Select-String -Path $day -Pattern '\[2026-07-21 15:39' | Where-Object { $_.Line -match 'KILL|PROXY|AUTH ERROR|Opening Cursor' } | ForEach-Object { $_.Line.Substring(0,[Math]::Min(240,$_.Line.Length)) }
Write-Host '--- 15:42 area ---'
Select-String -Path $day -Pattern '\[2026-07-21 15:42' | Where-Object { $_.Line -match 'KILL|PROXY|Opening Cursor|PROC_START' } | ForEach-Object { $_.Line.Substring(0,[Math]::Min(240,$_.Line.Length)) }
Write-Host '--- all session starts 15:xx ---'
Select-String -Path $day -Pattern 'session start v' | Where-Object { $_.Line -match '\[2026-07-21 15:' } | ForEach-Object { $_.Line.Substring(0,[Math]::Min(200,$_.Line.Length)) }
Write-Host '--- newest session full kill/open ---'
$last = Select-String -Path $day -Pattern 'session start v(\d+\.\d+)' | Select-Object -Last 1
$sid = if ($last.Line -match '\[([a-f0-9]{12})\]') { $Matches[1] } else { '?' }
$ver = $last.Matches[0].Groups[1].Value
Write-Host ("LATEST ver=$ver sid=$sid")
Select-String -Path $day -Pattern ("\[" + $sid + "\].*(LAUNCH_KILL|preserved_open|Opening Cursor|PROC_START_FAIL|PROC_START_OK|CURSOR_PROXY|AUTH ERROR|golden)") | ForEach-Object { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
# also check if a newer session than 11ce exists
Write-Host '--- last 5 session starts ---'
Select-String -Path $day -Pattern 'session start v' | Select-Object -Last 5 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(200,$_.Line.Length)) }
