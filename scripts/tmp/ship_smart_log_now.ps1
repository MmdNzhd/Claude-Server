$ErrorActionPreference='Stop'
$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
if (-not (Test-Path $local)) { throw "missing $local" }
$day = '20260719'
$remoteTmp = ".claude/logs/.connect-import-$PID.tmp"
$remoteDay = ".claude/logs/connect-$day.log"
$mk = 'mkdir -p $HOME/.claude/logs && chmod 700 $HOME/.claude $HOME/.claude/logs'
ssh -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=15 smart@192.168.250.70 $mk
if ($LASTEXITCODE -ne 0) { throw "mkdir failed" }
scp -o BatchMode=yes -o ControlMaster=no -o ConnectTimeout=120 -q $local "smart@192.168.250.70:$remoteTmp"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }
$finish = @"
cat `$HOME/$remoteTmp >> `$HOME/$remoteDay
rm -f `$HOME/$remoteTmp
chmod 600 `$HOME/$remoteDay
wc -c `$HOME/$remoteDay
ls -la `$HOME/.claude/logs
"@
ssh -o BatchMode=yes -o ControlMaster=no smart@192.168.250.70 $finish
