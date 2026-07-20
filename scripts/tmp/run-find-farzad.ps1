$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=25','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
& scp @($ssh + @('-q','D:\Smart\Claude-Code-Server\scripts\tmp\find-farzad.sh','claude-server-sepidz:/tmp/find-farzad.sh'))
if($LASTEXITCODE -ne 0){ throw "scp $LASTEXITCODE" }
& ssh @($ssh + @('claude-server-sepidz','bash /tmp/find-farzad.sh'))
