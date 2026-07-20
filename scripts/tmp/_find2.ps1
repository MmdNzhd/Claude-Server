Get-ChildItem scripts -Recurse -Filter 'cursor-auth-laptop.ps1' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
Get-ChildItem scripts/client/windows -File | ForEach-Object { $_.Name }
