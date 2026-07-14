$ErrorActionPreference = 'Continue'
$repo = (Get-Location).Path
$tmp = Join-Path $env:TEMP 'claude-update-quick'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
'20260701.1' | Set-Content (Join-Path $tmp 'connect-version.txt') -NoNewline
Copy-Item (Join-Path $repo 'scripts\client\windows\connect.ps1') (Join-Path $tmp 'connect.ps1')
$env:CLAUDE_CLIENT_BUNDLE = '/home/smart/claude-client-test'
Write-Host 'calling connect-update...'
& (Join-Path $repo 'scripts\client\windows\connect-update.ps1') -ScriptDir $tmp
Write-Host "done rc=$LASTEXITCODE ver=$((Get-Content (Join-Path $tmp 'connect-version.txt') -Raw).Trim())"
