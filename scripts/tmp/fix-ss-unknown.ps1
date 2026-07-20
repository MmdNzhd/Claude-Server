Set-Location 'D:\Smart\Claude-Code-Server'
# find foreign session / ss live clear in git-mode.ps1 and .sh
Select-String -Path scripts\client\git-mode.ps1,scripts\client\git-mode.sh -Pattern 'ss -ltn|live=0|rm -f.*claude-connect|foreign|Clear.*ConnectConf|Remove.*claude-connect' |
  Select-Object -First 40 | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }
