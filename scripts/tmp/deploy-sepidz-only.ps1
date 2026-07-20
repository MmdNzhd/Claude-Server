#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\Smart\Claude-Code-Server'
$SepidRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260715\claude-code'
& (Join-Path $ProjectRoot 'publish\deploy-client-bundles.ps1') `
  -ProjectRoot $ProjectRoot `
  -SepidClientRoot $SepidRoot `
  -SmartClientRoot $SepidRoot `
  -DeploySmart:$false `
  -DeploySepidz:$true
