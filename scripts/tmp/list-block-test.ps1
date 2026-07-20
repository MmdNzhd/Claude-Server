Get-ChildItem 'scripts\tmp\agent-block-test' | ForEach-Object { "{0}  {1} bytes  {2}" -f $_.Name, $_.Length, $_.FullName }
