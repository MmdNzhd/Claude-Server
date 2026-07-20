Get-ChildItem scripts/client -Recurse -File |
  Where-Object { $_.Name -match 'connect-ui|git-mode|connect\.(sh|ps1)|editor-launch' } |
  ForEach-Object { $_.FullName.Substring((Resolve-Path scripts/client).Path.Length+1) }
