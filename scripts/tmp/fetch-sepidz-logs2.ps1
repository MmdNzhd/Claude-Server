$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=25','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
& scp @($ssh + @('-q','D:\Smart\Claude-Code-Server\scripts\tmp\read-sepidz-logs2.sh','claude-server-sepidz:/tmp/read-sepidz-logs2.sh'))
if($LASTEXITCODE -ne 0){ throw "scp $LASTEXITCODE" }
& ssh @($ssh + @('claude-server-sepidz','bash /tmp/read-sepidz-logs2.sh'))
