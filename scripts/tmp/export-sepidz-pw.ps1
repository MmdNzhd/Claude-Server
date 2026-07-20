$ErrorActionPreference='Stop'
$local='D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1'
$c=Get-Content $local -Raw
$pw=$null
if ($c -match "SepidzSudoPassword\s*=\s*'([^']*)'") { $pw=$Matches[1] }
elseif ($c -match 'SepidzSudoPassword\s*=\s*"([^"]*)"') { $pw=$Matches[1] }
if (-not $pw) { throw 'SepidzSudoPassword not found' }
$out=Join-Path $env:TEMP 'sepidz-sudo.pw'
[System.IO.File]::WriteAllText($out, $pw)
Write-Output ("PWFILE=$out")
Write-Output ("PWLEN=" + $pw.Length)
