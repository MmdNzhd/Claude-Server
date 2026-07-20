$ErrorActionPreference = 'Stop'
$ssh = @(
  '-o','BatchMode=yes',
  '-o','ConnectTimeout=20',
  '-o','IdentitiesOnly=yes',
  '-o','IdentityAgent=none'
)
$src = 'D:\Smart\Claude-Code-Server\scripts\tmp\read-sepidz-logs.sh'
& scp @($ssh + @('-q', $src, 'claude-server-sepidz:/tmp/read-sepidz-logs.sh'))
if ($LASTEXITCODE -ne 0) { throw "scp failed: $LASTEXITCODE" }
& ssh @($ssh + @('claude-server-sepidz', 'bash /tmp/read-sepidz-logs.sh'))
if ($LASTEXITCODE -ne 0) { throw "ssh failed: $LASTEXITCODE" }
