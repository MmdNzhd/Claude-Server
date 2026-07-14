# test-connect-update-e2e.ps1 - live SSH/SCP update test (run on laptop)
$ErrorActionPreference = 'Continue'
$repo = (Get-Location).Path
$bundle = '/home/smart/claude-client-test'
$tmp = Join-Path $env:TEMP ('claude-update-test-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
'20260701.1' | Set-Content (Join-Path $tmp 'connect-version.txt') -NoNewline
Copy-Item (Join-Path $repo 'scripts\client\windows\connect.ps1') (Join-Path $tmp 'connect.ps1')
Write-Host '=== E2E live update test ==='
$env:CLAUDE_CLIENT_BUNDLE = $bundle
& (Join-Path $repo 'scripts\client\windows\connect-update.ps1') -ScriptDir $tmp
$rc = $LASTEXITCODE
$new = (Get-Content (Join-Path $tmp 'connect-version.txt') -Raw).Trim()
Write-Host "exit=$rc newver=$new"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($rc -eq 2 -and $new -eq '20260713.26') { Write-Host 'E2E LIVE UPDATE: PASS' -ForegroundColor Green; exit 0 }
Write-Host 'E2E LIVE UPDATE: FAIL' -ForegroundColor Red; exit 1
