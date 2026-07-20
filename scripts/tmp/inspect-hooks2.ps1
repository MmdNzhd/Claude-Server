$ErrorActionPreference='Continue'
Write-Output '==== user hooks ===='
@(
  "$env:USERPROFILE\.cursor\hooks.json",
  "$env:APPDATA\Cursor\hooks.json",
  'C:\Users\Smart\AppData\Roaming\Cursor\User\hooks.json'
) | ForEach-Object { if (Test-Path $_) { "FOUND $_"; Get-Content $_; "---" } else { "no $_" } }

Write-Output '==== server-side user hooks (on linux via... we are on windows laptop-exec) ===='
# Also show hooks-user.json and hooks-project.json from repo
Get-Content 'scripts\server\cursor-hooks\hooks-user.json' -ErrorAction SilentlyContinue
Write-Output '==== hooks-project.json ===='
Get-Content 'scripts\server\cursor-hooks\hooks-project.json' -ErrorAction SilentlyContinue

Write-Output '==== how install deploys hooks ===='
Select-String -Path 'scripts\server\commands\install.sh','scripts\server\laptop-exec*.sh' -Pattern 'hooks|laptop-exec-guard' -ErrorAction SilentlyContinue |
  Select-Object -First 40 | ForEach-Object { "{0}:{1}: {2}" -f ($_.Path|Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
