function Escape-BashSingleQuoted([string]$Text) { return $Text -replace "'", "'\''" }
$b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('printf PUSH_OK\\n'))
$r = "echo $b | base64 -d | bash"
$c = "timeout 20 bash -lc '$(Escape-BashSingleQuoted $r)'"
Write-Output "CMD=$c"
$out = ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o IdentityAgent=none sepidz@192.168.250.70 $c 2>&1
Write-Output "OUT=$out"
Write-Output "EXIT=$LASTEXITCODE"
