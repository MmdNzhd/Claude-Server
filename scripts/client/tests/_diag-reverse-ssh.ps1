# _diag-reverse-ssh.ps1 - show why server->laptop reverse SSH fails
$ErrorActionPreference = 'Continue'
$cfg = 'C:\Users\Smart\.config\claude-connect\connect.conf'
$c = @{}
if (Test-Path $cfg) {
    Get-Content $cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $c[$matches[1]] = $matches[2] } }
}
$lu = $c.LAPTOP_USER
if (-not $lu) { $lu = $env:USERNAME }
$port = 21003
if ($c.TUNNEL_SLOT -match '^\d+$') {
    $uid = (ssh -n -o BatchMode=yes -o ConnectTimeout=10 claude-server 'id -u' 2>$null).Trim()
    if ($uid -match '^\d+$') { $port = 20000 + [int]$uid + [int]$c.TUNNEL_SLOT }
}
Write-Host "LAPTOP_USER=$lu  PORT=$port" -ForegroundColor Cyan
$pub = (ssh -n -o BatchMode=yes -o ConnectTimeout=10 claude-server 'cat ~/.ssh/claude_laptop.pub 2>/dev/null').Trim()
$frag = ($pub -split '\s+')[1]
$admin = 'C:\ProgramData\ssh\administrators_authorized_keys'
$user = "C:\Users\$lu\.ssh\authorized_keys"
$adminHit = (Test-Path $admin) -and (Select-String -Path $admin -Pattern ([regex]::Escape($frag)) -Quiet -ErrorAction SilentlyContinue)
$userHit = (Test-Path $user) -and (Select-String -Path $user -Pattern ([regex]::Escape($frag)) -Quiet -ErrorAction SilentlyContinue)
Write-Host "administrators_authorized_keys: $(if ($adminHit) { 'FOUND' } else { 'MISSING' })"
Write-Host "user authorized_keys:           $(if ($userHit) { 'FOUND' } else { 'MISSING' })"
Write-Host ''
Write-Host 'Server reverse SSH (known_hosts_claude_mount):' -ForegroundColor Cyan
$cmd = "touch `$HOME/.ssh/known_hosts_claude_mount 2>/dev/null; chmod 600 `$HOME/.ssh/known_hosts_claude_mount 2>/dev/null; ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=`$HOME/.ssh/known_hosts_claude_mount -i ~/.ssh/claude_laptop -p $port ${lu}@127.0.0.1 cmd /c exit 0 2>&1"
$out = ssh -n -o BatchMode=yes -o ConnectTimeout=15 claude-server $cmd
$out | Select-Object -Last 8 | ForEach-Object { Write-Host $_ }
Write-Host "exit=$LASTEXITCODE"
