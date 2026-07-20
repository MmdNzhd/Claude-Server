Select-String -Path publish/publish.ps1 -Pattern 'DeploySmart|SmartOnly|SkipServerDeploy|deploy-client|finish-smart' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
