$c = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
1570..1610 | ForEach-Object { '{0,4}|{1}' -f $_, $c[$_-1] }
35..110 | ForEach-Object { '{0,4}|{1}' -f $_, $c[$_-1] }
