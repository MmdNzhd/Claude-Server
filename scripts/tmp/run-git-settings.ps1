$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
& scp -o BatchMode=yes -o ConnectTimeout=15 -q 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad_git_settings_and_smart.py' 'sepidz@192.168.250.70:/tmp/farzad_git_settings.py'
$nl=[char]10
$wrap='#!/bin/bash'+$nl+'PW=$(echo '+$pwB64+' | base64 -d)'+$nl+'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/farzad_git_settings.py'+$nl
[IO.File]::WriteAllText("$env:TEMP\gitset_wrap.sh", $wrap)
& scp -o BatchMode=yes -q "$env:TEMP\gitset_wrap.sh" 'sepidz@192.168.250.70:/tmp/gitset_wrap.sh'
& ssh -o BatchMode=yes -o ConnectTimeout=60 sepidz@192.168.250.70 'bash /tmp/gitset_wrap.sh'
