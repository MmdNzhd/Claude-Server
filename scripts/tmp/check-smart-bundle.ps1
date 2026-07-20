$ErrorActionPreference='Continue'
$key=Join-Path $env:USERPROFILE '.ssh\claude_laptop'
# Smart local check via ssh from laptop if possible
& ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null; ls /usr/local/share/claude-client/connect-update.ps1 2>&1 | head -3"
