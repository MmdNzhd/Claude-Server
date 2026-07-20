#Requires -Version 5.1
# finish-smart-deploy.ps1 - deploy Smart auto-update bundle from latest Desktop publish
& (Join-Path $PSScriptRoot 'deploy-smart-bundle.ps1') @args
