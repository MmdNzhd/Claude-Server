$client = Resolve-Path (Join-Path $PSScriptRoot '..')
$uiPath = Join-Path $client 'connect-ui.ps1'
$ui = Get-Content $uiPath -Raw
Write-Output "path=$uiPath"
Write-Output "match=$($ui -match 'Invoke-ConnectSilentUpdateCheck')"
Write-Output "length=$($ui.Length)"
Select-String -Path $uiPath -Pattern 'Invoke-ConnectSilentUpdateCheck' | ForEach-Object { "line=$($_.LineNumber)" }
