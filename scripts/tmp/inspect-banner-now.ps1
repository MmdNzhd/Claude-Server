Set-Location 'D:\Smart\Claude-Code-Server'
$lines=Get-Content scripts\client\git-mode.ps1
480..560 | ForEach-Object { '{0}|{1}' -f $_, $lines[$_-1] }
Write-Output '==== ENSURE ===='
860..930 | ForEach-Object { if($_ -le $lines.Count){ '{0}|{1}' -f $_, $lines[$_-1] } }
# parse check
$err=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path scripts\client\git-mode.ps1), [ref]$null, [ref]$err)
"parse_errors=$($err.Count)"
if($err){ $err | Select-Object -First 5 | ForEach-Object { $_.ToString() } }
