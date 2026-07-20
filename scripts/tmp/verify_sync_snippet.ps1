Select-String -Path scripts/client/connect-ui.ps1 -Pattern 'function Sync-ConnectLogToServer|LastConnectLogSyncOk|remoteTmp|TRACE/DEBUG|LinesSinceSync' |
  ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
try { . .\scripts\client\connect-ui.ps1; 'parse_ok' } catch { $_.Exception.Message; exit 1 }
