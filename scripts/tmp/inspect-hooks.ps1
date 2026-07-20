$ErrorActionPreference='Continue'
Write-Output '==== hook files ===='
Get-ChildItem -Recurse '.cursor\hooks','scripts\server\cursor-hooks' -ErrorAction SilentlyContinue |
  ForEach-Object { $_.FullName }
Write-Output '==== hooks.json ===='
@('.cursor\hooks.json','scripts\server\cursor-hooks\hooks.json') | ForEach-Object {
  if (Test-Path $_) { Write-Output "--- $_ ---"; Get-Content $_ }
}
Write-Output '==== guard script head ===='
Get-ChildItem -Recurse -Filter '*laptop-exec*guard*' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Output $_.FullName
  Get-Content $_.FullName -TotalCount 80
}
