# Find sshx calls that embed single-quoted grep/sed patterns (break mac sshx bash -lc wrap)
Select-String -Path scripts/client/git-mode.sh -Pattern "sshx \".*'[^']*'.*" |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }
