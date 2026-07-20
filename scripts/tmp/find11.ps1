$ErrorActionPreference='Continue'
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$dst = Join-Path $env:TEMP 'find11.log'
$fs=[IO.File]::Open($local,'Open','Read','ReadWrite')
try{$o=[IO.File]::Create($dst);try{$fs.CopyTo($o)}finally{$o.Close()}}finally{$fs.Close()}
Write-Host ("bytes={0} mtime={1}" -f (Get-Item $local).Length, (Get-Item $local).LastWriteTime)
Write-Host '=== search 20260719.11 ==='
Select-String -Path $dst -SimpleMatch '20260719.11' | Select-Object -First 20 | %{ $_.Line.Substring(0,[Math]::Min(160,$_.Line.Length)) }
Write-Host ("count_11={0}" -f @(Select-String -Path $dst -SimpleMatch '20260719.11').Count)
Write-Host '=== last 30 lines of file ==='
Get-Content $dst -Tail 30 | %{ $_.Substring(0,[Math]::Min(160,$_.Length)) }
Write-Host '=== lines after 13:00 ==='
Select-String -Path $dst -Pattern '\[2026-07-19 13:' | Select-Object -First 5 | %{ $_.Line.Substring(0,[Math]::Min(140,$_.Line.Length)) }
Write-Host ("count_13h={0}" -f @(Select-String -Path $dst -Pattern '\[2026-07-19 13:').Count)
Write-Host '=== BOOTSTRAP last 5 ==='
Select-String -Path $dst -SimpleMatch 'BOOTSTRAP' | Select-Object -Last 5 | %{ $_.Line.Substring(0,[Math]::Min(160,$_.Line.Length)) }
Write-Host '=== other log files ==='
Get-ChildItem (Join-Path $env:USERPROFILE '.config\claude-connect\logs') | Format-Table Name,Length,LastWriteTime -AutoSize
# server
$srv=Join-Path $env:TEMP 'find11-srv.log'
scp -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -q smart@192.168.250.70:.claude/logs/connect-20260719.log $srv
Write-Host ("server_bytes={0}" -f (Get-Item $srv).Length)
Write-Host '=== server 20260719.11 ==='
Select-String -Path $srv -SimpleMatch '20260719.11' | Select-Object -First 15 | %{ $_.Line.Substring(0,[Math]::Min(160,$_.Line.Length)) }
Write-Host ("server_count_11={0}" -f @(Select-String -Path $srv -SimpleMatch '20260719.11').Count)
Write-Host '=== server tail ==='
Get-Content $srv -Tail 15 | %{ $_.Substring(0,[Math]::Min(160,$_.Length)) }
Write-Host '=== server after 13: ==='
Write-Host ("srv_13h={0}" -f @(Select-String -Path $srv -Pattern '\[2026-07-19 13:').Count)
Select-String -Path $srv -Pattern '\[2026-07-19 13:' | Select-Object -First 10 | %{ $_.Line.Substring(0,[Math]::Min(150,$_.Line.Length)) }
Remove-Item $dst,$srv -Force -EA SilentlyContinue
