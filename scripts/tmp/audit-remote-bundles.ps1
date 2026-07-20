$ErrorActionPreference = 'Continue'
$fail = 0
function Check([string]$Label, [string]$Target) {
    Write-Host "`n=== $Label ($Target) ===" -ForegroundColor White
    $ver = (& ssh -o BatchMode=yes -o ConnectTimeout=15 $Target "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    if ($ver) { Write-Host "  version: v$ver" -ForegroundColor Green }
    else { Write-Host '  version: MISSING' -ForegroundColor Red; $script:fail++ }
    $ip = (& ssh -o BatchMode=yes -o ConnectTimeout=15 $Target "grep -o '192\.168\.[0-9.]*' /usr/local/share/claude-client/windows/connect.ps1 2>/dev/null | head -1").Trim()
    if ($ip) { Write-Host "  IP in bundle: $ip" -ForegroundColor Green } else { Write-Host '  IP: MISSING' -ForegroundColor Red; $script:fail++ }
    $install = (& ssh -o BatchMode=yes -o ConnectTimeout=15 $Target "test -x /usr/local/lib/claude-server/commands/install-client-bundle.sh && echo ok || echo missing").Trim()
    Write-Host "  install-client-bundle: $install" -ForegroundColor $(if ($install -eq 'ok') { 'Green' } else { 'Red' })
    if ($install -ne 'ok') { $script:fail++ }
    $mount = (& ssh -o BatchMode=yes -o ConnectTimeout=15 $Target "head -1 /usr/local/share/claude-client/mac/claude-mount.sh 2>/dev/null").Trim()
    if ($mount -match '^#!/') { Write-Host '  claude-mount.sh: present' -ForegroundColor Green }
    else { Write-Host '  claude-mount.sh: MISSING' -ForegroundColor Red; $script:fail++ }
}
Check 'Smart' 'smart@192.168.210.240'
Check 'Sepidz' 'sepidz@192.168.250.70'
Write-Host ''
if ($fail -eq 0) { Write-Host 'Remote bundle audit: ALL OK' -ForegroundColor Green; exit 0 }
Write-Host "Remote bundle audit: $fail issue(s)" -ForegroundColor Red; exit 1
