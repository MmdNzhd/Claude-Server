$client = Resolve-Path (Join-Path $PSScriptRoot '..')
$uiPath = Join-Path $client 'connect-ui.ps1'
Write-Output "client=$client"
Write-Output "uiPath=$uiPath"
Write-Output "exists=$(Test-Path -LiteralPath $uiPath)"
$ui = Get-Content $uiPath -Raw
Write-Output "match=$($ui -match 'Invoke-ConnectSilentUpdateCheck')"
Write-Output "length=$($ui.Length)"
