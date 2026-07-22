$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
$patterns = @('82924','75812','fd102c09b242','20:25:','SINGLE_INSTANCE','MULTI_INSTANCE','BOOTSTRAP')
foreach ($p in $patterns) {
  Write-Output "=== $p ==="
  Select-String -Path $log -Pattern $p -SimpleMatch | Select-Object -Last 12 | ForEach-Object { $_.Line }
}
