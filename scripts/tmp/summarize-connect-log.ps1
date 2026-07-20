$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
Write-Output ("size_mb={0:N1} mtime={1}" -f ((Get-Item $log).Length/1MB), (Get-Item $log).LastWriteTime)
Write-Output '==== last SESSION_LOOP / CONNECT begin ===='
Select-String -Path $log -Pattern 'SESSION_LOOP begin|ConnectVersion|version=|ENV version=|VERDICT_|AUTH: done|AUTH_SYNC: result|CURSOR_NOT|STEP end:|TUNNEL: connection dropped|RECOVERY_END|Opening Cursor|Launch' |
  Select-Object -Last 80 |
  ForEach-Object { $_.Line }
Write-Output ''
Write-Output '==== counts last ~hours (whole file sample via Select-String) ===='
$patterns=@{
  'CURSOR_NOT_FOUND'='CURSOR_NOT_FOUND'
  'AUTH fail'='AUTH:.*(fail|incomplete)|tokens_only=True'
  'AUTH ok'='AUTH: done complete=True|AUTH_SYNC: result.*ok=True'
  'CURSOR_ON_FOLDER_OK'='VERDICT_CODE=CURSOR_ON_FOLDER_OK'
  'tunnel drop'='TUNNEL: connection dropped'
  'version 20260717.3'='version=20260717\.3'
  'version 20260717.1'='version=20260717\.1'
  'version 20260717.2'='version=20260717\.2'
}
foreach($k in $patterns.Keys){
  $n=(Select-String -Path $log -Pattern $patterns[$k]).Count
  Write-Output ("{0}={1}" -f $k,$n)
}
Write-Output ''
Write-Output '==== first/last ENV version lines ===='
$envs=Select-String -Path $log -Pattern 'ENV version='
if($envs){ Write-Output ("FIRST: "+$envs[0].Line); Write-Output ("LAST: "+$envs[-1].Line) }
