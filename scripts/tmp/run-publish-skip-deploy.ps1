$ErrorActionPreference='Stop'
& 'D:\Smart\Claude-Code-Server\publish\publish.ps1' -SkipServerDeploy
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
