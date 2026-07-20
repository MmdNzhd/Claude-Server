$ErrorActionPreference = 'Stop'
& 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' `
  -ProjectRoot 'D:\Smart\Claude-Code-Server' `
  -SepidClientRoot 'D:\Smart\Claude-Code-Server\scripts\client' `
  -DeploySmart:$false `
  -DeploySepidz:$true
