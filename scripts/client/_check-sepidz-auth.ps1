$p = Join-Path (Get-Location) 'publish/sepidz-deploy.local.ps1'
if (-not (Test-Path $p)) { Write-Output 'FILE_MISSING'; exit 0 }
. $p
$pwLen = 0
if (Get-Variable -Name SepidzSudoPassword -ErrorAction SilentlyContinue) {
  $pwLen = ($SepidzSudoPassword | Measure-Object -Character).Characters
}
$user = if (Get-Variable SepidzSshUser -EA SilentlyContinue) { $SepidzSshUser } else { '(default)' }
$hostv = if (Get-Variable SepidzServerIp -EA SilentlyContinue) { $SepidzServerIp } else { '(default)' }
Write-Output "file=OK pw_len=$pwLen user=$user host=$hostv"
# also list variable names only
Get-Variable -Name Sepidz* -ErrorAction SilentlyContinue | ForEach-Object { "var=$($_.Name) set=$([bool]$_.Value) len=$((([string]$_.Value).Length))" }
