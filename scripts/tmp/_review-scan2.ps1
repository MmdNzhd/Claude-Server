Write-Host '=== Assert true variants ==='
Get-ChildItem scripts/client/tests -Filter *.ps1 | ForEach-Object {
  $i=0
  Get-Content $_.FullName | ForEach-Object {
    $i++
    if ($_ -match 'Assert\s*\(\s*\$true\b' -or $_ -match 'Assert\s+\$true\b') {
      Write-Host ("{0}:{1}:{2}" -f $_.Name, $i, $_.Trim())
    }
  }
}
Write-Host '=== soft asserts / vacuous ==='
Select-String -Path 'scripts/client/tests/*.ps1' -Pattern 'Assert \(\$true|Assert \$true|Assert \(1 -eq 1|Assert \(\$null -eq \$null' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '=== test PushConf content checks ==='
Select-String -Path 'scripts/client/tests/*.ps1' -Pattern "Escape-Bash|tr .*'|single.quot|apostrophe|O'Brien|Farzad|contains.*'|quot" | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '=== Get-FunctionSource PushConf body asserts ==='
Select-String -Path 'scripts/client/tests/test-connect-pipeline.ps1','scripts/client/tests/test-git-mode-deep.ps1' -Pattern 'pushConf|Push-Server|Escape|LAPTOP_USER|ActiveMount' | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
