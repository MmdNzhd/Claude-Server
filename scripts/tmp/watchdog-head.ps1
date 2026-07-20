1..80 | ForEach-Object {
  $l=(Get-Content 'D:\Smart\Claude-Code-Server\scripts\server\claude-watchdog.sh')[$_-1]
  "{0,4}|{1}" -f $_, $l
}
Write-Output '=== connect-ui durable comment ==='
200..290 | ForEach-Object {
  $l=(Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.sh')[$_-1]
  "{0,4}|{1}" -f $_, $l
}
