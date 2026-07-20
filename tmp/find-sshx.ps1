Select-String -Path scripts\client\mac\connect.sh,scripts\client\git-mode.sh -Pattern '^sshx\(\)|ControlMaster|ControlPath' |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)) }
# sqlite merge
Select-String -Path scripts\client\git-mode.sh -Pattern 'cursor_sqlite_merge_pairs|INSERT OR REPLACE|cursorAuth' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)) } | Select-Object -First 25
