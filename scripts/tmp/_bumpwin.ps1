$p='scripts/client/windows/connect.ps1'
$c=Get-Content $p -Raw
$c2=[regex]::Replace($c,"ConnectVersion = '20260717\.\d+'","ConnectVersion = '20260717.11'")
Set-Content $p -Value $c2 -NoNewline
Select-String -Path $p -Pattern 'ConnectVersion' | Select-Object -First 1 | ForEach-Object { $_.Line.Trim() }
Select-String -Path scripts/client/mac/connect.sh -Pattern 'base64-wrap|CONNECT_VERSION|base64' | Select-Object -First 5 | ForEach-Object { $_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)) }
Select-String -Path scripts/client/git-mode.sh -Pattern 'grep \^LAPTOP_USER|unexpected EOF' | ForEach-Object { $_.Line.Trim() }
