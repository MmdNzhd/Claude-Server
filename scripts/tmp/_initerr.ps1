Select-String -Path scripts/client/git-mode.sh,scripts/client/mac/connect.sh -Pattern 'INIT_SERVER_SESSION|could not configure|initialize_server_session|step_fail' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
