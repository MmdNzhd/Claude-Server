$g=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
Write-Output '=== Mac soft_fail block ==='
745..785 | ForEach-Object { "{0,4}|{1}" -f $_, $g[$_-1] }
$c=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh'
Write-Output '=== Mac session keys ==='
914..960 | ForEach-Object { "{0,4}|{1}" -f $_, $c[$_-1] }
Write-Output '=== Mac disconnect markers ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh' -Pattern 'user_quit|fallthrough_recover|_action=""' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
$bash = @('C:\Program Files\Git\bin\bash.exe','C:\Program Files\Git\usr\bin\bash.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($bash) {
  & $bash -n 'D:/Smart/Claude-Code-Server/scripts/client/mac/connect.sh'; Write-Output "connect.sh bash -n exit=$LASTEXITCODE"
  & $bash -n 'D:/Smart/Claude-Code-Server/scripts/client/git-mode.sh'; Write-Output "git-mode.sh bash -n exit=$LASTEXITCODE"
} else { Write-Output 'no git bash' }
Write-Output '=== versions ==='
Get-Content D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt
Get-Content D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt
(Select-String -Path D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1 -Pattern 'ConnectVersion\s*=' | Select-Object -First 1).Line.Trim()
# Win useVk PostDisconnect
Write-Output '=== Win useVk ==='
Select-String -Path D:\Smart\Claude-Code-Server\scripts\client\windows\connect-ui.ps1 -Pattern 'useVk' | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== Win CONTEXT ActiveProjectId ==='
Select-String -Path D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1 -Pattern 'ActiveProjectId' | Select-Object -First 8 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
