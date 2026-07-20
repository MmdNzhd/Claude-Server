$lines=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\connect-diagnostic.ps1'
80..160 | ForEach-Object { "{0,4}|{1}" -f $_, $lines[$_-1] }
