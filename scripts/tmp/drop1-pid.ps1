$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
Select-String -Path $log -Pattern '38352|35732|10376|TUNNEL_STOP|killing bg|orphan' |
  ForEach-Object { 'L{0}|{1}' -f $_.LineNumber, $_.Line }
