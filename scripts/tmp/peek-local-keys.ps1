$c=Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
[regex]::Matches($c, '^\s*\$?(\w+)\s*=', 'Multiline') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
