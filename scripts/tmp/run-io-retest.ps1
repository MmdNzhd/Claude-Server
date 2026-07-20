$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
& scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\sepidz_io_retest.py' 'sepidz@192.168.250.70:/tmp/sepidz_io_retest.py'
$nl=[char]10
$wrap='#!/bin/bash'+$nl+'PW=$(echo '+$pwB64+' | base64 -d)'+$nl+'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/sepidz_io_retest.py'+$nl+'ec=$?'+$nl+'echo IO_EXIT=$ec'+$nl+'exit $ec'+$nl
[IO.File]::WriteAllText("$env:TEMP\io_retest_wrap.sh",$wrap)
& scp -o BatchMode=yes -q "$env:TEMP\io_retest_wrap.sh" 'sepidz@192.168.250.70:/tmp/io_retest_wrap.sh'
& ssh -o BatchMode=yes -o ConnectTimeout=180 sepidz@192.168.250.70 'bash /tmp/io_retest_wrap.sh'
exit $LASTEXITCODE
