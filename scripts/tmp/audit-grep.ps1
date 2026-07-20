$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$patterns = 'session start','BOOTSTRAP','SINGLE_INSTANCE','EXIT_WAIT','LOG_SYNC_FAIL','session end','^\[.*\] .*UPDATE:'
Select-String -Path $log -Pattern $patterns | Select-Object LineNumber,Line | ForEach-Object { "$($_.LineNumber): $($_.Line)" }
