$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')
& scp @($ssh + @('-q','D:\Smart\Claude-Code-Server\scripts\tmp\read-sepidz-logs3.sh','claude-server-sepidz:/tmp/read-sepidz-logs3.sh'))
& ssh @($ssh + @('claude-server-sepidz','bash /tmp/read-sepidz-logs3.sh'))
