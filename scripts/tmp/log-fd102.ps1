$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Select-String -Path $log -Pattern 'fd102c09b242' | Select-String -Pattern 'session start|SINGLE|MULTI|BOOTSTRAP' | ForEach-Object { $_.Line }
Select-String -Path $log -Pattern '56492' | Select-Object -First 10 | ForEach-Object { $_.Line }
