Set-Location 'D:\Smart\Claude-Code-Server'
$path='scripts\client\editor-launch.sh'
$lines=Get-Content $path
# show context 130-160
130..160 | ForEach-Object { '{0}|{1}' -f $_, $lines[$_-1] }
