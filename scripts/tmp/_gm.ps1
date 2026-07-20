foreach ($p in @('scripts/client/git-mode.sh','scripts/client/mac/git-mode.sh')) {
  if (Test-Path $p) {
    $c = Get-Content $p -Raw
    Write-Output ("$p len=$($c.Length) warn=$($c -match 'warn_foreign_server_session')")
  } else { Write-Output "$p MISSING" }
}
# How publish copies git-mode into mac package
Select-String -Path publish/publish.ps1 -Pattern 'git-mode' | Select-Object -First 15 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
