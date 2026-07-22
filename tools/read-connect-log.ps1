$LogDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$Today = Get-Date -Format 'yyyyMMdd'
$LogFile = Join-Path $LogDir "connect-$Today.log"
Write-Output "logfile=$LogFile"
if (-not (Test-Path -LiteralPath $LogFile)) { Write-Output 'LOG_MISSING'; exit 0 }
$pat = 'BOOTSTRAP|UPDATE|FAIL|legacy|redirect|exe_only|up_to_date|healed|cleaned'
Get-Content -LiteralPath $LogFile | Select-String -Pattern $pat | Select-Object -Last 40 | ForEach-Object { $_.Line }
