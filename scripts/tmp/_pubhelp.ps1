Select-String -Path publish/publish.ps1 -Pattern 'param\(|SkipVersionBump|DeploySmart|OutBase|claude-code-client' |
  Select-Object -First 40 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
