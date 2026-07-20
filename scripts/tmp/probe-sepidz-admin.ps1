$Server = 'smart@192.168.250.70'
$cmds = @(
    'whoami; id; sudo -l 2>&1 | head -20',
    'test -x /usr/local/bin/claude-server && claude-server --help | head -5 || echo no-claude-server',
    'ls -la /usr/local/share/ 2>&1 | head -10',
    'python3 --version; command -v unzip || echo no-unzip'
)
foreach ($c in $cmds) {
    Write-Host "`n--- $c ---" -ForegroundColor DarkGray
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $Server $c 2>&1
}
