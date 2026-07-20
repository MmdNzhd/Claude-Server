$p = 'scripts/client/windows/connect.ps1'
$c = Get-Content $p -Raw
$c2 = [regex]::Replace($c, "ConnectVersion = '20260717\.\d+'", "ConnectVersion = '20260717.9'")
if ($c -eq $c2) { Write-Output 'NO_CHANGE'; Select-String -Path $p -Pattern 'ConnectVersion' | Select-Object -First 1 | ForEach-Object { $_.Line.Trim() } }
else { Set-Content -Path $p -Value $c2 -NoNewline; Write-Output 'BUMPED' }
Get-Content scripts/client/mac/connect-version.txt
Get-Content scripts/client/windows/connect-version.txt -ErrorAction SilentlyContinue
Select-String -Path scripts/client/mac/connect.sh -Pattern '^CONNECT_VERSION=' | ForEach-Object { $_.Line }
# verify update insert
Select-String -Path scripts/client/mac/connect.sh -Pattern 'Re-run client auto-update' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Select-String -Path scripts/client/mac/connect-update.sh -Pattern 'never default to local whoami|remote_user=.smart' | ForEach-Object { $_.Line.Trim() }
