$log='D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
Write-Output ("exists=" + (Test-Path $log) + " size=" + (Get-Item $log).Length)
Write-Output '=== session starts / UPDATE / versions ==='
Select-String -Path $log -Pattern 'session start|UPDATE:|CONNECT_VERSION=|applied_ok|need_relaunch|20260719\.(2[0-9]|3[0-9])' | ForEach-Object {
  "{0}:{1}" -f $_.LineNumber, $_.Line.Trim()
} | Select-Object -Last 80
Write-Output '=== version histogram ==='
Select-String -Path $log -Pattern 'v20260719\.\d+|CONNECT_VERSION=20260719\.\d+|local_ver=20260719\.\d+|up_to_date v20260719\.\d+|applied_ok.*20260719' -AllMatches | ForEach-Object {
  $_.Matches | ForEach-Object { $_.Value }
} | Group-Object | Sort-Object Count -Descending | ForEach-Object { "{0,5} {1}" -f $_.Count, $_.Name }
Write-Output '=== last 15 lines ==='
Get-Content $log -Tail 15
Write-Output '=== first session start ==='
Select-String -Path $log -Pattern 'session start' | Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }
